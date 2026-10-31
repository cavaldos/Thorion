import Defaults
import Foundation
import smc_power

extension MagSafeLEDState: Defaults.Serializable {}

enum StatusIconStyle: String, Defaults.Serializable, CaseIterable, Identifiable {
    case hidden
    case logo
    case status
    case macOS27
    case macOS26
    case macOS26Colored
    case iOSNative

    var id: String { rawValue }

    /// Styles that already draw the percentage inside the battery body.
    var showsPercentageInside: Bool {
        self == .macOS27 || self == .iOSNative
    }

    var supportsPercentageNextToIcon: Bool {
        self != .hidden && !showsPercentageInside
    }
}

/// Shared by every control that edits `chargeLimit`, so they all snap to the same values.
enum ChargeLimitScale {
    static let range = 50...100
    static let step = 5

    static func snapped(_ percentage: Double) -> Int {
        let stepped = Int((percentage / Double(step)).rounded()) * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

extension Defaults.Keys {
    // General
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)

    // Updates
    static let automaticallyCheckForUpdates = Key<Bool>("automaticallyCheckForUpdates", default: true)
    static let lastNotifiedUpdateVersion = Key<String?>("lastNotifiedUpdateVersion")

    // Status Icon
    static let statusIconStyle = Key<StatusIconStyle>("statusIconStyle", default: .macOS26Colored)
    static let showPercentageNextToIcon = Key<Bool>("showPercentageNextToIcon", default: true)

    // Notifications
    static let disableNotifications = Key<Bool>("disableNotifications", default: false)
    static let showChargingStatusChangedNotification = Key<Bool>(
        "showChargingStatusChangedNotification", default: true)

    // Menu Dashboard
    static let showTimeTillDischarge = Key<Bool>("showTimeTillDischarge", default: true)
    static let showBatteryCycleCount = Key<Bool>("showBatteryCycleCount", default: true)
    static let showBatteryHealth = Key<Bool>("showBatteryHealth", default: true)
    static let showBatteryTemperature = Key<Bool>("showBatteryTemperature", default: false)
    static let showPowerSource = Key<Bool>("showPowerSource", default: false)
    static let showUptime = Key<Bool>("showUptime", default: true)
    static let showBatteryMode = Key<Bool>("showBatteryMode", default: true)
    static let showInternalPower = Key<Bool>("showInternalPower", default: true)
    static let showExternalPower = Key<Bool>("showExternalPower", default: true)
    static let showSystemPower = Key<Bool>("showSystemPower", default: false)
    static let showAdapterRatedPower = Key<Bool>("showAdapterRatedPower", default: false)
    static let showCPUTemperature = Key<Bool>("showCPUTemperature", default: false)
    static let showGPUTemperature = Key<Bool>("showGPUTemperature", default: false)
    static let showPowerDistribution = Key<Bool>("showPowerDistribution", default: false)
    static let showEnergyApps = Key<Bool>("showEnergyApps", default: true)
    static let energyAppsExpanded = Key<Bool>("energyAppsExpanded", default: true)
    /// When off, the power distribution diagram only reads new data while the menu or the
    /// dashboard is open.
    static let updatePowerDataInBackground = Key<Bool>("updatePowerDataInBackground", default: false)

    // Charging
    static let manageCharging = Key<Bool>("manageCharging", default: false)
    static let chargeLimit = Key<Int>("chargeLimit", default: 80)
    static let sailingMode = Key<Bool>("sailingMode", default: true)
    static let sailingModeLimit = Key<Int>("sailingModeLimit", default: 5)
    // Off by default: above the limit the Mac runs on the adapter with charging paused
    // (green LED), and only the Discharge button drains the battery back to the limit.
    static let automaticDischarge = Key<Bool>("automaticDischarge", default: false)
    static let disableSleepUntilChargeLimit = Key<Bool>("disableSleepUntilChargeLimit", default: false)
    static let nativeChargeLimitApplied = Key<Bool>("nativeChargeLimitApplied", default: false)

    // Charging - Heat Protection
    static let enableHeatProtectionMode = Key<Bool>(
        "enableHeatProtectionMode", default: true)
    static let heatProtectionLimit = Key<Int>("heatProtectionLimit", default: 40)

    // Charging - MagSafe LED Control
    static let manageMagSafeLED = Key<Bool>("manageMagSafeLED", default: true)
    static let heatProtectionMagSafeLEDState = Key<MagSafeLEDState>(
        "heatProtectionMagSafeLEDState", default: MagSafeLEDState.blinkOrangeSlow)
    // Advanced
    static let useHardwarePercentage = Key<Bool>("useHardwarePercentage", default: false)
}
