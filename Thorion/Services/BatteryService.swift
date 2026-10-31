import Defaults
import Foundation
import Observation
import os.log
import smc_power

/// How charging is paused. The SMC keys are preferred where they exist; macOS 27 removed
/// them on Apple Silicon, which leaves the charge limit that macOS enforces itself.
enum ChargeInhibitMethod {
    case unavailable
    case smc
    case nativeChargeLimit
}

enum XPCError: LocalizedError {
    case helperUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            "XPC helper is unavailable"
        case .commandFailed(let message):
            "Command failed: \(message)"
        }
    }
}

@MainActor
@Observable
class BatteryService {
    var metrics = BatteryMetrics()
    var adapterMetrics = AdapterMetrics()
    var systemPowerMetrics = SystemPowerMetrics()
    private(set) var history: [BatteryHistorySample] = []
    private(set) var controlState = BatteryControlState()
    private(set) var deviceCapabilities = DeviceCapabilities(
        chargingControl: false,
        adapterControl: false,
        hasMagSafe: false,
        magsafeLEDControl: false
    )
    private(set) var chargeInhibitMethod = ChargeInhibitMethod.unavailable

    private let nativeChargeLimit = NativeChargeLimitService()
    private let xpcManager = SMCReaderConnection(
        serviceName: "com.thorion.app.helper"
    )
    private let ioKitService = IOKitService()

    private var ioKitMonitorTask: Task<Void, Never>?
    private var smcPollTask: Task<Void, Never>?
    private var delayedPollTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var backgroundPollTask: Task<Void, Never>?
    private var backgroundPollLoop: Task<Void, Never>?

    // The menu and the Settings dashboard can both be open at once, so polling
    // stops only when every requester has released it.
    private var fastPollingRequestCount = 0

    private static let historySampleInterval: Duration = .seconds(60)
    /// Slower than the 1 s poll used while the menu or dashboard is open, since nothing
    /// is watching the readings in between.
    private static let backgroundPollInterval: Duration = .seconds(5)
    private static let historyRetention: TimeInterval = 24 * 60 * 60

    private let logger = Logger(
        subsystem: "com.thorion.app",
        category: "BatteryService"
    )

    init() {
        logger.info("BatteryService initialized")
        xpcManager.connect()
        startIOKitMonitoring()
        startRecordingHistory()
        startBackgroundPolling()
    }

    func loadCapabilities() async {
        let smcCapabilities = await loadSMCCapabilities()

        if smcCapabilities.chargingControl {
            chargeInhibitMethod = .smc
        } else if nativeChargeLimit.isAvailable {
            chargeInhibitMethod = .nativeChargeLimit
        } else {
            chargeInhibitMethod = .unavailable
        }

        let capabilities = DeviceCapabilities(
            chargingControl: chargeInhibitMethod != .unavailable,
            adapterControl: smcCapabilities.adapterControl,
            hasMagSafe: smcCapabilities.hasMagSafe,
            magsafeLEDControl: smcCapabilities.magsafeLEDControl
        )
        self.deviceCapabilities = capabilities
        logger.info(
            "Capabilities loaded: charging=\(String(describing: self.chargeInhibitMethod)), adapter=\(capabilities.adapterControl), magSafe=\(capabilities.hasMagSafe)"
        )
    }

    private func loadSMCCapabilities() async -> DeviceCapabilities {
        let unsupported = DeviceCapabilities(
            chargingControl: false,
            adapterControl: false,
            hasMagSafe: false,
            magsafeLEDControl: false
        )
        let logger = self.logger
        guard
            let helper = xpcManager.getHelper(errorHandler: { error in
                logger.error(
                    "XPC error loading capabilities: \(error.localizedDescription)")
            })
        else {
            logger.warning("Helper unavailable for capability probe")
            return unsupported
        }

        return await withCheckedContinuation { continuation in
            helper.getCapabilities { chargingControl, adapterControl, hasMagSafe, magsafeLEDControl in
                continuation.resume(
                    returning: DeviceCapabilities(
                        chargingControl: chargingControl,
                        adapterControl: adapterControl,
                        hasMagSafe: hasMagSafe,
                        magsafeLEDControl: magsafeLEDControl
                    )
                )
            }
        }
    }

    private func startIOKitMonitoring() {
        logger.info("Starting IOKit monitoring in main app")
        ioKitMonitorTask = Task {
            for await (newBatteryMetrics, newAdapterMetrics) in self.ioKitService.metricsStream() {
                guard !Task.isCancelled else { break }
                self.handleIOKitUpdate(newBatteryMetrics, adapterUpdate: newAdapterMetrics)
            }
        }
    }

    private func startRecordingHistory() {
        historyTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.historySampleInterval)
                guard let self, !Task.isCancelled else { return }
                // The first sample is taken when IOKit delivers its first reading,
                // so an empty history means there is nothing real to record yet.
                if !self.history.isEmpty {
                    self.recordHistorySample()
                }
            }
        }
    }

    private func recordHistorySample() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-Self.historyRetention)
        history.removeAll { $0.date < cutoff }
        history.append(
            BatteryHistorySample(
                date: now,
                batteryPercentage: metrics.batteryPercentage,
                hardwareBatteryPercentage: metrics.hardwareBatteryPercentage,
                temperature: metrics.batteryTemperature > 0 ? metrics.batteryTemperature : nil
            )
        )
    }

    /// Keeps the power readings fresh while the menu and dashboard are closed, but only
    /// when "Update in background" is on.
    private func startBackgroundPolling() {
        backgroundPollTask = Task { [weak self] in
            for await enabled in Defaults.updates(.updatePowerDataInBackground) {
                guard let self else { return }
                if enabled {
                    self.startBackgroundPollLoop()
                } else {
                    self.stopBackgroundPollLoop()
                }
            }
        }
    }

    private func startBackgroundPollLoop() {
        guard backgroundPollLoop == nil else { return }
        logger.info("Enabling background SMC polling")
        backgroundPollLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // The fast poll already covers this while the menu or dashboard is open.
                if self.smcPollTask == nil {
                    await self.pollSMCOnce()
                }
                try? await Task.sleep(for: Self.backgroundPollInterval)
            }
        }
    }

    private func stopBackgroundPollLoop() {
        guard backgroundPollLoop != nil else { return }
        logger.info("Disabling background SMC polling")
        backgroundPollLoop?.cancel()
        backgroundPollLoop = nil
    }

    func enableFastPolling() {
        fastPollingRequestCount += 1
        guard smcPollTask == nil else { return }

        logger.info("Enabling fast SMC polling")

        smcPollTask = Task {
            await self.pollSMCOnce()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                await self.pollSMCOnce()
            }
        }
    }

    func scheduleSinglePoll(delay: Duration = .seconds(3)) {
        delayedPollTask?.cancel()
        delayedPollTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self.pollSMCOnce()
        }
    }

    func disableFastPolling() {
        guard fastPollingRequestCount > 0 else {
            logger.warning("Fast polling not enabled")
            return
        }

        fastPollingRequestCount -= 1
        guard fastPollingRequestCount == 0 else { return }

        logger.info("Disabling fast SMC polling")
        smcPollTask?.cancel()
        smcPollTask = nil
    }

    private func fetchSMCBatteryData() async -> SMCBatteryReading? {
        let logger = self.logger
        guard
            let helper = xpcManager.getHelper(errorHandler: { error in
                logger.error(
                    "XPC error during SMC battery poll: \(error.localizedDescription)"
                )
            })
        else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            helper.readBatteryMetrics { batteryVoltage, batteryCurrent, batteryPower in
                continuation.resume(
                    returning: SMCBatteryReading(
                        batteryVoltage: batteryVoltage,
                        batteryCurrent: batteryCurrent,
                        batteryPower: batteryPower
                    )
                )
            }
        }
    }

    private func fetchSMCAdapterData() async -> SMCAdapterReading? {
        let logger = self.logger
        guard
            let helper = xpcManager.getHelper(errorHandler: { error in
                logger.error(
                    "XPC error during SMC adapter poll: \(error.localizedDescription)"
                )
            })
        else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            helper.readAdapterMetrics { adapterVoltage, adapterCurrent, adapterPower in
                continuation.resume(
                    returning: SMCAdapterReading(
                        adapterVoltage: adapterVoltage,
                        adapterCurrent: adapterCurrent,
                        adapterPower: adapterPower
                    )
                )
            }
        }
    }

    private func fetchSystemPowerData() async -> SMCSystemPowerReading? {
        let logger = self.logger
        guard
            let helper = xpcManager.getHelper(errorHandler: { error in
                logger.error(
                    "XPC error during SMC system power poll: \(error.localizedDescription)"
                )
            })
        else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            // The six values are positional and all optional. The argument labels
            // at the call below are the only thing tying them to their names, so
            // the ordering must stay in step with Helper.readSystemPower.
            helper.readSystemPower {
                totalWatts, cpuWatts, displayWatts, adapterRatedWatts, cpuTemperature, gpuTemperature in
                continuation.resume(
                    returning: SMCSystemPowerReading(
                        totalWatts: totalWatts?.doubleValue,
                        cpuWatts: cpuWatts?.doubleValue,
                        displayWatts: displayWatts?.doubleValue,
                        adapterRatedWatts: adapterRatedWatts?.doubleValue,
                        cpuTemperature: cpuTemperature?.doubleValue,
                        gpuTemperature: gpuTemperature?.doubleValue
                    )
                )
            }
        }
    }

    private func applySystemPowerReading(_ reading: SMCSystemPowerReading) {
        let updatedSystem = SystemPowerMetrics(
            totalWatts: reading.totalWatts,
            cpuWatts: reading.cpuWatts,
            displayWatts: reading.displayWatts,
            adapterRatedWatts: reading.adapterRatedWatts,
            cpuTemperature: reading.cpuTemperature,
            gpuTemperature: reading.gpuTemperature
        )

        if updatedSystem != systemPowerMetrics {
            systemPowerMetrics = updatedSystem
        }
    }

    private func pollSMCOnce() async {
        async let batteryData = fetchSMCBatteryData()
        async let adapterData = fetchSMCAdapterData()
        async let systemPowerData = fetchSystemPowerData()

        // Applied ahead of the guard below so a failed system power read cannot
        // suppress the battery and adapter readings, and vice versa.
        if let systemPowerReading = await systemPowerData {
            applySystemPowerReading(systemPowerReading)
        } else {
            logger.warning("No helper available for SMC system power polling")
        }

        guard let batteryReading = await batteryData, let adapterReading = await adapterData else {
            logger.error("No helper available for SMC battery polling")
            return
        }

        var updatedBattery = metrics
        updatedBattery.batteryVoltage = batteryReading.batteryVoltage
        updatedBattery.batteryCurrent = batteryReading.batteryCurrent
        updatedBattery.batteryPower = batteryReading.batteryPower

        var updatedAdapter = adapterMetrics
        updatedAdapter.adapterVoltage = adapterReading.adapterVoltage
        updatedAdapter.adapterCurrent = adapterReading.adapterCurrent
        updatedAdapter.adapterPower = adapterReading.adapterPower

        // SMC reports faster than IOKit can update, so refine isCharging
        // using the actual power flow direction.
        if updatedAdapter.adapterConnected {
            updatedBattery.isCharging = batteryReading.batteryPower > 0
        }

        if updatedBattery != metrics {
            metrics = updatedBattery
        }
        if updatedAdapter != adapterMetrics {
            adapterMetrics = updatedAdapter
        }
        updateControlState(from: updatedBattery, adapter: updatedAdapter)
    }

    /// `systemPowerMetrics` is deliberately not merged in here. IOKit exposes no
    /// system-wide power draw or die temperature, so there is no IOKit value to
    /// carry over; the copy-back below only exists to protect the voltage,
    /// current and power fields that IOKit does overwrite. Touching
    /// `systemPowerMetrics` in this function would reset it to all-nil on every
    /// battery notification, so it is written only by the SMC poll.
    private func handleIOKitUpdate(_ newBatteryMetrics: BatteryMetrics, adapterUpdate: AdapterMetrics) {
        logger.debug("Received IOKit update")

        var updatedBattery = newBatteryMetrics
        updatedBattery.batteryVoltage = metrics.batteryVoltage
        updatedBattery.batteryCurrent = metrics.batteryCurrent
        updatedBattery.batteryPower = metrics.batteryPower

        if updatedBattery != metrics {
            metrics = updatedBattery
        }

        if history.isEmpty {
            recordHistorySample()
        }

        var updatedAdapter = adapterUpdate
        updatedAdapter.adapterVoltage = adapterMetrics.adapterVoltage
        updatedAdapter.adapterCurrent = adapterMetrics.adapterCurrent
        updatedAdapter.adapterPower = adapterMetrics.adapterPower

        if updatedAdapter != adapterMetrics {
            adapterMetrics = updatedAdapter
        }

        updateControlState(from: updatedBattery, adapter: updatedAdapter)
    }

    private func updateControlState(from metrics: BatteryMetrics, adapter: AdapterMetrics) {
        let newState = BatteryControlState(
            batteryPercentage: metrics.batteryPercentage,
            hardwareBatteryPercentage: metrics.hardwareBatteryPercentage,
            adapterConnected: adapter.adapterConnected,
            batteryTemperature: metrics.batteryTemperature
        )
        if newState != controlState {
            controlState = newState
        }
    }

    /// `nativeLimit` is the displayed percentage macOS should stop at, and is only used
    /// when charging is paused through the macOS charge limit.
    func manageBatteryCharging(enabled: Bool, nativeLimit: Int) async throws {
        switch chargeInhibitMethod {
        case .smc:
            try await manageSMCCharging(enabled: enabled)
        case .nativeChargeLimit:
            try nativeChargeLimit.apply(limit: nativeLimit)
        case .unavailable:
            throw XPCError.commandFailed("Charging control is not supported on this device")
        }
    }

    /// Lifts a macOS charge limit that Thorion applied. A no-op when the SMC is used or
    /// when the limit was set by someone else.
    func restoreNativeChargeLimit() throws {
        try nativeChargeLimit.restore()
    }

    private func manageSMCCharging(enabled: Bool) async throws {
        try await ChargingHelperManager.shared.send { helper, reply in
            helper.manageBatteryCharging(enabled: enabled, reply: reply)
        }
    }

    func manageExternalPower(enabled: Bool) async throws {
        try await ChargingHelperManager.shared.send { helper, reply in
            helper.manageExternalPower(enabled: enabled, reply: reply)
        }
    }

    func manageMagsafeLED(target: MagSafeLEDState) async throws {
        let rawValue = target.rawValue
        try await ChargingHelperManager.shared.send { helper, reply in
            helper.manageMagsafeLED(target: rawValue, reply: reply)
        }
    }

    func stop() {
        logger.info("BatteryService stopping")
        ioKitMonitorTask?.cancel()
        ioKitMonitorTask = nil
        smcPollTask?.cancel()
        smcPollTask = nil
        fastPollingRequestCount = 0
        delayedPollTask?.cancel()
        delayedPollTask = nil
        historyTask?.cancel()
        historyTask = nil
        backgroundPollTask?.cancel()
        backgroundPollTask = nil
        stopBackgroundPollLoop()
        xpcManager.disconnect()
    }
}
