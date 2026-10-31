import AppKit
import Defaults
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
class MenuViewModel {
    /// Shown when the helper reports a value the Mac does not expose. Rendering
    /// an unsupported reading as "0" would read as a real measurement.
    private static let unavailableValueText = "N/A"

    private let batteryService: BatteryService
    private let chargeManager: ChargeManager
    private let bootTimestamp: Date?

    var powerSourceText: String = "Battery"
    var timeRemainingText: String = "Calculating..."
    var uptimeText: String = "0m"
    var batteryModeText: String = "Unknown"
    var batteryTemperatureText: String = "0°C"
    var externalInputText: String = "0V @ 0A"
    var internalInputText: String = "0V @ 0A"
    var systemPowerText: String = unavailableValueText
    var adapterRatedPowerText: String = unavailableValueText
    var cpuTemperatureText: String = unavailableValueText
    var gpuTemperatureText: String = unavailableValueText
    var cycleCountText: String = "0"
    var batteryHealthText: String = "100%"

    var displayPercentage: Int = 0
    var chargingMode: ChargingMode = .discharging
    /// The smoothed readings behind the power distribution diagram.
    private(set) var powerFlow = PowerFlowSnapshot()
    var batteryPower: Double { powerFlow.batteryWatts }
    var adapterPower: Double { powerFlow.adapterWatts }
    var systemPower: Double { powerFlow.systemWatts }
    var isLowPowerModeEnabled: Bool = false

    var chargeLimitOverrideActive: Bool { chargeManager.chargeLimitOverrideActive }
    var forceDischargeActive: Bool { chargeManager.forceDischargeActive }
    var canTopUp: Bool { chargeManager.canTopUp }
    var canForceDischarge: Bool { chargeManager.canForceDischarge }
    var isSailing: Bool { chargeManager.isSailing }
    var adapterConnected: Bool = false

    let energyAppsMonitor = EnergyAppsMonitor()

    private var metricsObservation: Task<Void, Never>?
    private var settingsObservation: Task<Void, Never>?
    private var uptimeTask: Task<Void, Never>?
    private var powerModeObservation: Task<Void, Never>?

    // The menu and the dashboard can be open at the same time, so live updates stop
    // only once both have closed.
    private var liveViewCount = 0
    @ObservationIgnored private var powerFlowUpdatedAt: ContinuousClock.Instant?

    /// How quickly the diagram follows new readings. CPU power swings by several watts
    /// from one second to the next, so raw readings made every number jump.
    private static let powerFlowSmoothingTime = 2.5

    /// Whether the power distribution values should follow new readings. Without the
    /// background option they stay as they were while nothing shows them, so the
    /// diagram is not redrawn for nobody.
    private var shouldUpdatePowerFlow: Bool {
        liveViewCount > 0 || Defaults[.updatePowerDataInBackground]
    }

    init(batteryService: BatteryService, chargeManager: ChargeManager) {
        self.batteryService = batteryService
        self.chargeManager = chargeManager
        self.bootTimestamp = SystemService.bootTimestamp()
        startObservingMetrics()
        startObservingSettings()
        startObservingPowerMode()
    }

    private func startObservingMetrics() {
        metricsObservation = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.updateFormattedValues(
                    from: self.batteryService.metrics,
                    adapter: self.batteryService.adapterMetrics
                )
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.batteryService.metrics
                        _ = self.batteryService.adapterMetrics
                        _ = self.batteryService.systemPowerMetrics
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
                [.useHardwarePercentage, .updatePowerDataInBackground], initial: false
            ) {
                guard let self else { return }
                self.updateFormattedValues(
                    from: self.batteryService.metrics,
                    adapter: self.batteryService.adapterMetrics
                )
            }
        }
    }

    private func startObservingPowerMode() {
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

        powerModeObservation = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: .NSProcessInfoPowerStateDidChange,
                object: ProcessInfo.processInfo
            )
            for await _ in notifications {
                self?.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    func toggleChargeLimitOverride() {
        chargeManager.toggleChargeLimitOverride()
    }

    func toggleForceDischarge() {
        chargeManager.toggleForceDischarge()
    }

    private func updateFormattedValues(from metrics: BatteryMetrics, adapter: AdapterMetrics) {
        let useHardware = Defaults[.useHardwarePercentage]
        let percentage =
            useHardware
            ? metrics.hardwareBatteryPercentage : metrics.batteryPercentage
        displayPercentage = percentage

        let derivedPowerSource = derivePowerSource(battery: metrics, adapter: adapter)

        switch derivedPowerSource {
        case .battery:
            powerSourceText = "Battery"
        case .acAdapter:
            powerSourceText = "Power Adapter"
        case .both:
            powerSourceText = "Battery & Power Adapter"
        }

        let formatted = formatTimeRemaining(minutes: metrics.timeRemaining)
        if !formatted.isEmpty {
            timeRemainingText = formatted
        } else if derivedPowerSource == .acAdapter && !metrics.isCharging {
            timeRemainingText = "Not Charging"
        } else {
            timeRemainingText = "Calculating..."
        }

        updateUptimeText()

        if derivedPowerSource == .acAdapter {
            if metrics.isCharging {
                chargingMode = .charging
                batteryModeText = "Charging"
            } else {
                chargingMode = .pluggedIn
                batteryModeText = "Plugged In (Not Charging)"
            }
        } else {
            chargingMode = .discharging
            batteryModeText = "Discharging"
        }

        batteryTemperatureText =
            "\(metrics.batteryTemperature.formatted(.number.precision(.fractionLength(1))))°C"

        let voltageFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        let currentFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))

        externalInputText =
            "\(adapter.adapterVoltage.formatted(voltageFormat))V @ \(adapter.adapterCurrent.formatted(currentFormat))A"

        internalInputText =
            "\(metrics.batteryVoltage.formatted(voltageFormat))V @ \(metrics.batteryCurrent.formatted(currentFormat))A"

        let systemPowerMetrics = batteryService.systemPowerMetrics
        let wattFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        let temperatureFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))

        systemPowerText = Self.format(systemPowerMetrics.totalWatts, format: wattFormat, suffix: " W")
        adapterRatedPowerText = Self.format(
            systemPowerMetrics.adapterRatedWatts, format: wattFormat, suffix: " W")
        cpuTemperatureText = Self.format(
            systemPowerMetrics.cpuTemperature, format: temperatureFormat, suffix: "°C")
        gpuTemperatureText = Self.format(
            systemPowerMetrics.gpuTemperature, format: temperatureFormat, suffix: "°C")

        if shouldUpdatePowerFlow {
            updatePowerFlow(
                target: PowerFlowSnapshot(
                    adapterWatts: max(adapter.adapterPower, 0),
                    batteryWatts: metrics.batteryPower,
                    cpuWatts: systemPowerMetrics.cpuWatts,
                    displayWatts: systemPowerMetrics.displayWatts,
                    measuredSystemWatts: systemPowerMetrics.totalWatts
                )
            )
        }
        adapterConnected = adapter.adapterConnected

        cycleCountText = "\(metrics.cycleCount)"
        batteryHealthText = "\(metrics.batteryHealth)%"
    }

    /// Eases toward new readings over a few seconds. After a long gap, such as the
    /// menu being closed, the new reading is taken as is.
    private func updatePowerFlow(target: PowerFlowSnapshot) {
        let now = ContinuousClock.now
        defer { powerFlowUpdatedAt = now }

        guard let powerFlowUpdatedAt else {
            powerFlow = target
            return
        }
        let elapsed = now - powerFlowUpdatedAt
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let weight = 1 - exp(-seconds / Self.powerFlowSmoothingTime)
        let blended = powerFlow.blended(toward: target, weight: weight)
        if blended != powerFlow {
            powerFlow = blended
        }
    }

    private static func format(
        _ value: Double?,
        format: FloatingPointFormatStyle<Double>,
        suffix: String
    ) -> String {
        guard let value else { return unavailableValueText }
        return value.formatted(format) + suffix
    }

    private func derivePowerSource(battery: BatteryMetrics, adapter: AdapterMetrics) -> PowerSource {
        guard adapter.adapterConnected else { return .battery }

        if adapter.adapterPower == 0 {
            return .battery
        } else if battery.batteryPower >= 0 {
            return .acAdapter
        } else {
            return .both
        }
    }

    private func updateUptimeText() {
        guard let bootTimestamp else {
            uptimeText = "Unknown"
            return
        }

        let elapsed = Duration.seconds(Date().timeIntervalSince(bootTimestamp))
        uptimeText = elapsed.formatted(.units(
            allowed: [.days, .hours, .minutes],
            width: .condensedAbbreviated,
            zeroValueUnits: .hide
        ))
    }

    private func startUptimeTimer() {
        guard uptimeTask == nil else { return }

        uptimeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.updateUptimeText()
            }
        }
    }

    private func stopUptimeTimer() {
        uptimeTask?.cancel()
        uptimeTask = nil
    }

    /// Called when the menu or the dashboard appears: polls the SMC every second and
    /// lets the power distribution diagram follow the readings.
    func beginLiveUpdates() {
        liveViewCount += 1
        // The first poll starts right away, and its reading should replace the old
        // one rather than be eased toward.
        if liveViewCount == 1, !Defaults[.updatePowerDataInBackground] {
            powerFlowUpdatedAt = nil
        }
        batteryService.enableFastPolling()
    }

    func endLiveUpdates() {
        guard liveViewCount > 0 else { return }
        liveViewCount -= 1
        batteryService.disableFastPolling()
    }

    func menuWillOpen() {
        updateUptimeText()
        startUptimeTimer()
        beginLiveUpdates()
        if Defaults[.showEnergyApps] {
            energyAppsMonitor.start()
        }
    }

    func menuDidClose() {
        stopUptimeTimer()
        endLiveUpdates()
        energyAppsMonitor.stop()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func formatTimeRemaining(minutes: Int) -> String {
        if minutes < 0 {
            return ""
        }
        let hours = minutes / 60
        let mins = minutes % 60
        return String(format: "%02d:%02d", hours, mins)
    }

    deinit {
        MainActor.assumeIsolated {
            metricsObservation?.cancel()
            settingsObservation?.cancel()
            uptimeTask?.cancel()
            powerModeObservation?.cancel()
        }
    }
}
