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
    private var hasReachedChargeLimit = false
    private var lastNotifiedChargingState: Bool?
    private var ledIsManaged = false
    private var lastEffectiveChargeLimit: Int?
    private var adapterDisconnectReportedAt: ContinuousClock.Instant?
    private var adapterDisconnectRecheck: Task<Void, Never>?

    private static let adapterDisconnectGracePeriod: Duration = .seconds(3)

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

    private func evaluate(controlState: BatteryControlState) {
        var stateWasCleared = false
        let adapterConnected = resolveAdapterConnection(reported: controlState.adapterConnected)

        if adapterConnected != lastAdapterConnected {
            logger.info("Adapter connection changed: \(adapterConnected)")
            lastAdapterConnected = adapterConnected
            clearCachedState()
            stateWasCleared = true
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
            stateWasCleared = true
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
        if forceDischargeActive, batteryPercentage <= Defaults[.chargeLimit] {
            logger.info("Discharge finished: battery is back at the charge limit")
            forceDischargeActive = false
        }

        let chargeLimit = chargeLimitOverrideActive ? 100 : Defaults[.chargeLimit]

        if stateWasCleared && Defaults[.sailingMode]
            && batteryPercentage >= chargeLimit - Defaults[.sailingModeLimit] {
            hasReachedChargeLimit = true
        }

        // Raising the limit means "charge up to the new limit", even when the battery
        // already sits within the sailing range below it.
        if let lastEffectiveChargeLimit, chargeLimit > lastEffectiveChargeLimit {
            hasReachedChargeLimit = false
        }
        lastEffectiveChargeLimit = chargeLimit

        var desiredCharging: Bool
        var desiredAdapter: Bool
        var chargingStateReason: String

        if batteryPercentage > chargeLimit {
            hasReachedChargeLimit = true
            desiredCharging = false
            desiredAdapter = Defaults[.automaticDischarge] ? false : true
            chargingStateReason = "Battery is above the charge limit of \(chargeLimit)%"
        } else if batteryPercentage == chargeLimit {
            hasReachedChargeLimit = true
            desiredCharging = false
            desiredAdapter = true
            chargingStateReason = "Battery has reached the charge limit of \(chargeLimit)%"
        } else if Defaults[.sailingMode] {
            let sailingThreshold = chargeLimit - Defaults[.sailingModeLimit]
            let inSailingRange = batteryPercentage >= sailingThreshold

            if inSailingRange && hasReachedChargeLimit {
                desiredCharging = false
                desiredAdapter = true
                chargingStateReason = "Sailing mode is maintaining charge below \(chargeLimit)%"
            } else {
                let droppedOutOfSailingRange = !inSailingRange && hasReachedChargeLimit
                hasReachedChargeLimit = false
                desiredCharging = true
                desiredAdapter = true
                if inSailingRange {
                    chargingStateReason = "Charging to reach charge limit of \(chargeLimit)%"
                } else if droppedOutOfSailingRange {
                    chargingStateReason =
                        "Battery dropped below sailing threshold of \(sailingThreshold)%"
                } else {
                    chargingStateReason = "Battery is below the charge limit of \(chargeLimit)%"
                }
            }
        } else {
            desiredCharging = true
            desiredAdapter = true
            chargingStateReason = "Battery is below the charge limit of \(chargeLimit)%"
        }

        let heatProtectionActive = Defaults[.enableHeatProtectionMode]
            && controlState.batteryTemperature > Double(Defaults[.heatProtectionLimit])
        if heatProtectionActive {
            desiredCharging = false
            chargingStateReason =
                "Battery temperature exceeds \(Defaults[.heatProtectionLimit])°C"
        }

        if forceDischargeActive {
            desiredCharging = false
            desiredAdapter = false
        }

        isSailing = Defaults[.sailingMode] && hasReachedChargeLimit && !forceDischargeActive
            && batteryPercentage <= chargeLimit
            && batteryPercentage >= chargeLimit - Defaults[.sailingModeLimit]

        let capabilities = batteryService.deviceCapabilities

        if capabilities.chargingControl {
            // powerd compares its limit with the displayed percentage, so the native limit
            // is always expressed in that scale. While charging it is set to the charge
            // limit so macOS stops by itself even while the Mac sleeps; with hardware
            // percentages the two scales differ, so Thorion pauses charging itself.
            let nativeLimit: Int
            if desiredCharging {
                nativeLimit = Defaults[.useHardwarePercentage]
                    ? NativeChargeLimitService.supportedRange.upperBound : chargeLimit
            } else {
                nativeLimit = controlState.batteryPercentage
            }
            setCharging(enabled: desiredCharging, nativeLimit: nativeLimit)
            sendChargingStateNotification(
                charging: desiredCharging, reason: chargingStateReason
            )
        }
        if capabilities.adapterControl {
            setAdapter(enabled: desiredAdapter)
        }
        if capabilities.hasMagSafe, capabilities.magsafeLEDControl {
            updateLED(
                charging: desiredCharging,
                adapterEnabled: desiredAdapter,
                heatProtectionActive: heatProtectionActive
            )
        }

        let shouldPreventSleep = Defaults[.disableSleepUntilChargeLimit]
            && desiredCharging
        updateSleepAssertion(shouldPreventSleep: shouldPreventSleep)
    }

    /// Green while charging is paused, orange while charging, and blinking orange while
    /// the Mac runs off the battery with the adapter connected.
    private func updateLED(charging: Bool, adapterEnabled: Bool, heatProtectionActive: Bool) {
        guard Defaults[.manageMagSafeLED] else {
            // Hand the LED back to macOS once, rather than leaving the last color stuck.
            if ledIsManaged {
                ledIsManaged = false
                setLED(state: .reset)
            }
            return
        }

        let state: MagSafeLEDState
        if !adapterEnabled {
            state = .blinkOrangeSlow
        } else if heatProtectionActive {
            state = Defaults[.heatProtectionMagSafeLEDState]
        } else if charging {
            state = .orange
        } else {
            state = .green
        }

        ledIsManaged = true
        setLED(state: state)
    }

    private func clearCachedState() {
        lastNotifiedChargingState = nil
        hasReachedChargeLimit = false
    }

    private func resetToDefaults(restoreNativeChargeLimit shouldRestoreNativeChargeLimit: Bool) {
        hasReachedChargeLimit = false
        isSailing = false
        lastManageChargingEnabled = false
        updateSleepAssertion(shouldPreventSleep: false)
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
            ledIsManaged = false
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
                logger.error("Failed to set charging to \(enabled): \(error)")
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
                logger.error("Failed to set adapter to \(enabled): \(error)")
            }
        }
    }

    private func setLED(state: MagSafeLEDState) {
        logger.info("Setting MagSafe LED: \(String(describing: state))")
        Task {
            do {
                try await batteryService.manageMagsafeLED(target: state)
            } catch {
                logger.error("Failed to set LED to \(String(describing: state)): \(error)")
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
        forceDischargeActive || currentBatteryPercentage > Defaults[.chargeLimit]
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
        updateSleepAssertion(shouldPreventSleep: false)
        restoreNativeChargeLimit()
    }
}
