import Defaults
import Foundation
import IOKit.pwr_mgt
import Observation
import UserNotifications
import os.log
import smc_power

@MainActor
@Observable
class ChargeManager {
    private let batteryService: BatteryService

    private var metricsObservation: Task<Void, Never>?
    private var settingsObservation: Task<Void, Never>?

    private var lastAdapterConnected: Bool?
    private var lastManageChargingEnabled: Bool?
    private var policy = ChargePolicy()

    /// What Thorion last asked the Mac for. When it changes the Mac needs a few seconds to
    /// follow, and the status has to catch up with it.
    private struct Enforcement: Equatable {
        var charging: Bool
        var adapterEnabled: Bool
        var chargeLimit: Int
    }
    private var lastEnforcement: Enforcement?
    private var lastNotifiedChargingState: Bool?
    /// The color Thorion holds the MagSafe LED at, or nil while macOS controls it.
    private var managedLEDState: MagSafeLEDState?
    private var ledRefreshTask: Task<Void, Never>?
    /// Until then the LED is checked every `ledSettlingRefreshInterval`, because macOS may
    /// still be reacting to a charging change and write its own color.
    private var ledSettlingDeadline: ContinuousClock.Instant?
    private var adapterDisconnectReportedAt: ContinuousClock.Instant?
    private var adapterDisconnectRecheck: Task<Void, Never>?

    private static let adapterDisconnectGracePeriod: Duration = .seconds(3)
    /// The SMC keeps the LED color written last, and Thorion is not the only writer. macOS
    /// writes its own color too: with the adapter plugged in and charging paused at the macOS
    /// limit, the key read orange (04) although nothing else had run. Another charge limiter
    /// also leaves its color behind when it quits (green was still set, with the adapter
    /// unplugged, after AlDente had run). So the color is sent again at this interval while
    /// the adapter is connected. The helper only writes when the SMC holds something else, so
    /// a refresh costs one read.
    private static let ledRefreshInterval: Duration = .seconds(10)
    /// macOS starts or stops charging from about 2 to over 10 seconds after being asked (see
    /// `BatteryService.pollWhileSettling`), and may set its own LED color when it does. For
    /// this long after a charging change the LED is checked every `ledSettlingRefreshInterval`.
    private static let ledSettlingDuration: Duration = .seconds(30)
    private static let ledSettlingRefreshInterval: Duration = .seconds(2)

    private(set) var chargeLimitOverrideActive = false
    private(set) var forceDischargeActive = false
    private(set) var isSailing = false
    private var sleepAssertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)

    private let logger = Logger(
        subsystem: "com.thorion.app",
        category: "ChargeManager"
    )

    init(batteryService: BatteryService) {
        self.batteryService = batteryService
        startObservingMetrics()
        startObservingSettings()
    }

    private func startObservingMetrics() {
        metricsObservation = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.evaluate(controlState: self.batteryService.controlState)
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.batteryService.controlState
                        // Commands sent while the helper could not start were lost, so
                        // they are sent again once it is back.
                        _ = ChargingHelperManager.shared.helperStatus
                        _ = ChargingHelperManager.shared.isResponding
                    } onChange: {
                        Task { @MainActor in
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    private func startObservingSettings() {
        settingsObservation = Task { [weak self] in
            for await _ in Defaults.updates(
                [
                    .manageCharging, .sailingMode, .automaticDischarge,
                    .disableSleepUntilChargeLimit,
                    .enableHeatProtectionMode, .manageMagSafeLED, .useHardwarePercentage,
                    .chargeLimit, .sailingModeLimit, .heatProtectionLimit,
                    .heatProtectionMagSafeLEDState,
                ],
                initial: false
            ) {
                guard let self else { return }
                self.evaluate(controlState: self.batteryService.controlState)
            }
        }
    }

    /// Whether the adapter counts as connected. A disconnect only counts once it has
    /// lasted `adapterDisconnectGracePeriod`, because the adapter reports itself as gone
    /// for under a second whenever charging starts or stops while macOS renegotiates
    /// power. Treating those blips as unplugging reset the sailing state, so charging
    /// paused again right after it was resumed.
    private func resolveAdapterConnection(reported: Bool) -> Bool {
        if reported {
            adapterDisconnectReportedAt = nil
            adapterDisconnectRecheck?.cancel()
            adapterDisconnectRecheck = nil
            return true
        }

        let now = ContinuousClock.now
        let reportedAt = adapterDisconnectReportedAt ?? now
        adapterDisconnectReportedAt = reportedAt

        guard lastAdapterConnected == true, now - reportedAt < Self.adapterDisconnectGracePeriod else {
            return false
        }

        if adapterDisconnectRecheck == nil {
            adapterDisconnectRecheck = Task { [weak self] in
                try? await Task.sleep(for: Self.adapterDisconnectGracePeriod)
                guard !Task.isCancelled, let self else { return }
                self.adapterDisconnectRecheck = nil
                self.evaluate(controlState: self.batteryService.controlState)
            }
        }
        return true
    }

    /// Whether charging can only be paused through the macOS charge limit, which cannot hold
    /// the battery below 80%.
    var usesNativeChargeLimit: Bool {
        batteryService.chargeInhibitMethod == .nativeChargeLimit
    }

    /// Whether the adapter can be cut right now: the Mac supports it and the helper that does
    /// it is working. Without that a command to cut it would silently do nothing.
    var canCutAdapter: Bool {
        batteryService.deviceCapabilities.adapterControl && ChargingHelperManager.shared.isWorking
    }

    /// Whether a limit below what macOS can hold is held by cutting the adapter, so the Mac
    /// runs on its battery between charges. Only with Automatic discharge on.
    var holdsByCuttingAdapter: Bool {
        usesNativeChargeLimit
            && ChargeLimitScale.holdsByCuttingAdapter(
                automaticDischarge: Defaults[.automaticDischarge], canCutAdapter: canCutAdapter)
    }

    /// The saved limit, raised to the lowest level this Mac can really hold unless the battery
    /// is held by cutting the adapter. This is the limit that decisions and the Discharge
    /// button go by.
    var effectiveChargeLimit: Int {
        ChargeLimitScale.effectiveLimit(
            Defaults[.chargeLimit],
            usingNativeChargeLimit: usesNativeChargeLimit,
            holdsByCuttingAdapter: holdsByCuttingAdapter)
    }

    private func evaluate(controlState: BatteryControlState) {
        let adapterConnected = resolveAdapterConnection(reported: controlState.adapterConnected)

        if adapterConnected != lastAdapterConnected {
            logger.info("Adapter connection changed: \(adapterConnected)")
            lastAdapterConnected = adapterConnected
            clearCachedState()
        }

        guard Defaults[.manageCharging], adapterConnected else {
            if chargeLimitOverrideActive, !adapterConnected {
                chargeLimitOverrideActive = false
            }
            if forceDischargeActive, !adapterConnected {
                forceDischargeActive = false
            }
            // Unplugging leaves the macOS limit alone: it has no effect on battery, and
            // rewriting it on every plug event made powerd renegotiate with the
            // charger, which reported further plug events and kept the cycle going.
            resetToDefaults(restoreNativeChargeLimit: !Defaults[.manageCharging])
            return
        }

        if lastManageChargingEnabled != true {
            lastManageChargingEnabled = true
            clearCachedState()
        }

        let batteryPercentage =
            Defaults[.useHardwarePercentage]
            ? controlState.hardwareBatteryPercentage : controlState.batteryPercentage

        // Top Up is a one-time charge to full. It ends once the battery is full, and the
        // battery then sits above the limit with charging paused.
        if chargeLimitOverrideActive,
            batteryPercentage >= 100 || controlState.batteryPercentage >= 100 {
            logger.info("Top Up finished: battery is full")
            chargeLimitOverrideActive = false
        }

        // Discharge drains the battery back down to the limit, then hands power back to
        // the adapter.
        if forceDischargeActive, batteryPercentage <= effectiveChargeLimit {
            logger.info("Discharge finished: battery is back at the charge limit")
            forceDischargeActive = false
        }

        let decision = policy.decide(
            percentage: batteryPercentage,
            temperature: controlState.batteryTemperature,
            settings: ChargePolicy.Settings(
                chargeLimit: chargeLimitOverrideActive ? 100 : Defaults[.chargeLimit],
                sailingMode: Defaults[.sailingMode],
                sailingModeLimit: Defaults[.sailingModeLimit],
                automaticDischarge: Defaults[.automaticDischarge],
                heatProtection: Defaults[.enableHeatProtectionMode],
                heatProtectionLimit: Defaults[.heatProtectionLimit],
                forceDischarge: forceDischargeActive,
                lowestHoldablePercentage: ChargeLimitScale.lowestHoldablePercentage(
                    usingNativeChargeLimit: usesNativeChargeLimit),
                canCutAdapter: canCutAdapter
            )
        )
        isSailing = decision.isSailing

        let enforcement = Enforcement(
            charging: decision.charging,
            adapterEnabled: decision.adapterEnabled,
            chargeLimit: decision.chargeLimit
        )
        if enforcement != lastEnforcement {
            lastEnforcement = enforcement
            logger.info(
                "Charging decision: charging=\(decision.charging), adapter=\(decision.adapterEnabled), limit=\(decision.chargeLimit)% (\(decision.reason, privacy: .public))"
            )
            batteryService.pollWhileSettling()
            // Restarted below by `updateLED`, so the next check comes after the short interval.
            ledSettlingDeadline = ContinuousClock.now + Self.ledSettlingDuration
            ledRefreshTask?.cancel()
            ledRefreshTask = nil
        }

        let capabilities = batteryService.deviceCapabilities

        if capabilities.chargingControl {
            let nativeLimit = NativeChargeLimitService.limit(
                charging: decision.charging,
                chargeLimit: decision.chargeLimit,
                displayedPercentage: controlState.batteryPercentage,
                hardwarePercentage: controlState.hardwareBatteryPercentage,
                usesHardwarePercentage: Defaults[.useHardwarePercentage]
            )
            setCharging(enabled: decision.charging, nativeLimit: nativeLimit)
            sendChargingStateNotification(
                charging: decision.charging, reason: decision.reason
            )
        }
        if capabilities.adapterControl {
            setAdapter(enabled: decision.adapterEnabled)
        }
        if capabilities.hasMagSafe, capabilities.magsafeLEDControl {
            updateLED(decision.indicator)
        }

        let shouldPreventSleep = Defaults[.disableSleepUntilChargeLimit]
            && decision.charging
        updateSleepAssertion(shouldPreventSleep: shouldPreventSleep)
    }

    /// Orange while charging, green once the battery is at or above the limit, including while
    /// the Mac drains it down to the limit with the adapter connected.
    private func updateLED(_ indicator: ChargePolicy.Indicator) {
        guard Defaults[.manageMagSafeLED] else {
            // Hand the LED back to macOS once, rather than leaving the last color stuck.
            if managedLEDState != nil {
                stopManagingLED()
                setLED(state: .reset)
            }
            return
        }

        let state = indicator.ledState(heatProtection: Defaults[.heatProtectionMagSafeLEDState])
        if state != managedLEDState {
            logger.info("MagSafe LED: \(String(describing: state), privacy: .public)")
            managedLEDState = state
        }
        setLED(state: state)
        startRefreshingLED()
    }

    private func startRefreshingLED() {
        guard ledRefreshTask == nil else { return }
        ledRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = self?.ledRefreshDelay ?? Self.ledRefreshInterval
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                // Commands to a helper that stopped answering only pile up. `evaluate` sends
                // the color again once it answers.
                guard let state = self.managedLEDState, ChargingHelperManager.shared.isWorking else {
                    continue
                }
                self.setLED(state: state)
            }
        }
    }

    private var ledRefreshDelay: Duration {
        if let ledSettlingDeadline, ContinuousClock.now < ledSettlingDeadline {
            return Self.ledSettlingRefreshInterval
        }
        return Self.ledRefreshInterval
    }

    /// Stops holding the LED at a color. The caller hands it back to macOS.
    private func stopManagingLED() {
        if managedLEDState != nil {
            logger.info("MagSafe LED: back to macOS")
        }
        managedLEDState = nil
        ledRefreshTask?.cancel()
        ledRefreshTask = nil
    }

    private func clearCachedState() {
        lastNotifiedChargingState = nil
        lastEnforcement = nil
        policy.reset()
    }

    private func resetToDefaults(restoreNativeChargeLimit shouldRestoreNativeChargeLimit: Bool) {
        policy.reset()
        lastEnforcement = nil
        isSailing = false
        lastManageChargingEnabled = false
        updateSleepAssertion(shouldPreventSleep: false)
        stopManagingLED()
        if shouldRestoreNativeChargeLimit {
            restoreNativeChargeLimit()
        }
        guard ChargingHelperManager.shared.isInstalled else { return }
        let capabilities = batteryService.deviceCapabilities
        if capabilities.chargingControl, batteryService.chargeInhibitMethod == .smc {
            setCharging(enabled: true, nativeLimit: NativeChargeLimitService.supportedRange.upperBound)
        }
        if capabilities.adapterControl {
            setAdapter(enabled: true)
        }
        if capabilities.hasMagSafe, capabilities.magsafeLEDControl {
            setLED(state: .reset)
        }
    }

    private func restoreNativeChargeLimit() {
        do {
            try batteryService.restoreNativeChargeLimit()
        } catch {
            logger.error("Failed to restore the macOS charge limit: \(error.localizedDescription)")
        }
    }

    private func setCharging(enabled: Bool, nativeLimit: Int) {
        logger.info("Setting charging: \(enabled)")
        Task {
            do {
                try await batteryService.manageBatteryCharging(enabled: enabled, nativeLimit: nativeLimit)
                batteryService.scheduleSinglePoll()
            } catch {
                logger.error("Failed to set charging to \(enabled): \(error, privacy: .public)")
            }
        }
    }

    private func setAdapter(enabled: Bool) {
        logger.info("Setting adapter: \(enabled)")
        Task {
            do {
                try await batteryService.manageExternalPower(enabled: enabled)
                batteryService.scheduleSinglePoll()
            } catch {
                logger.error("Failed to set adapter to \(enabled): \(error, privacy: .public)")
            }
        }
    }

    private func setLED(state: MagSafeLEDState) {
        logger.debug("Sending MagSafe LED: \(String(describing: state), privacy: .public)")
        Task {
            do {
                try await batteryService.manageMagsafeLED(target: state)
            } catch {
                logger.error("Failed to set LED to \(String(describing: state), privacy: .public): \(error, privacy: .public)")
            }
        }
    }

    private func updateSleepAssertion(shouldPreventSleep: Bool) {
        let assertionActive = sleepAssertionID != IOPMAssertionID(kIOPMNullAssertionID)

        if shouldPreventSleep && !assertionActive {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Thorion: Charging towards charge limit" as CFString,
                &sleepAssertionID
            )
            if result == kIOReturnSuccess {
                logger.info("Sleep assertion created")
            } else {
                logger.error("Failed to create sleep assertion: \(result)")
            }
        } else if !shouldPreventSleep && assertionActive {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
            logger.info("Sleep assertion released")
        }
    }

    private func sendChargingStateNotification(charging: Bool, reason: String?) {
        guard charging != lastNotifiedChargingState else { return }
        lastNotifiedChargingState = charging

        guard !Defaults[.disableNotifications],
            Defaults[.showChargingStatusChangedNotification]
        else { return }

        let content = UNMutableNotificationContent()
        content.title = charging ? String(localized: "Charging Resumed") : String(localized: "Charging Paused")
        if let reason {
            content.body = reason
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "chargingStateChanged",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.error("Failed to deliver notification: \(error)")
            }
        }
    }

    private var currentBatteryPercentage: Int {
        let state = batteryService.controlState
        return Defaults[.useHardwarePercentage] ? state.hardwareBatteryPercentage : state.batteryPercentage
    }

    /// Top Up only has something to do while the battery is not yet full.
    var canTopUp: Bool {
        chargeLimitOverrideActive
            || (currentBatteryPercentage < 100 && batteryService.controlState.batteryPercentage < 100)
    }

    /// Discharge only has something to do while the battery is above the limit.
    var canForceDischarge: Bool {
        forceDischargeActive || currentBatteryPercentage > effectiveChargeLimit
    }

    func toggleChargeLimitOverride() {
        guard chargeLimitOverrideActive || canTopUp else { return }
        chargeLimitOverrideActive.toggle()
        if chargeLimitOverrideActive {
            forceDischargeActive = false
        }
        evaluate(controlState: batteryService.controlState)
    }

    func toggleForceDischarge() {
        guard forceDischargeActive || canForceDischarge else { return }
        forceDischargeActive.toggle()
        if forceDischargeActive {
            chargeLimitOverrideActive = false
        }
        evaluate(controlState: batteryService.controlState)
    }

    /// Called on quit. The charging helper resets the SMC by itself when the app's
    /// connection drops, but a macOS charge limit outlives the app, so it is lifted here.
    func stop() {
        metricsObservation?.cancel()
        metricsObservation = nil
        settingsObservation?.cancel()
        settingsObservation = nil
        adapterDisconnectRecheck?.cancel()
        adapterDisconnectRecheck = nil
        ledRefreshTask?.cancel()
        ledRefreshTask = nil
        updateSleepAssertion(shouldPreventSleep: false)
        restoreNativeChargeLimit()
    }
}
