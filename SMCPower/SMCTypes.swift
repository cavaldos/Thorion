import Foundation

public struct SMCBatteryReading: Sendable {
    public let batteryVoltage: Double
    public let batteryCurrent: Double
    public let batteryPower: Double

    public init(
        batteryVoltage: Double,
        batteryCurrent: Double,
        batteryPower: Double
    ) {
        self.batteryVoltage = batteryVoltage
        self.batteryCurrent = batteryCurrent
        self.batteryPower = batteryPower
    }
}

public struct SMCSystemPowerReading: Sendable {
    public let totalWatts: Double?
    public let cpuWatts: Double?
    public let displayWatts: Double?
    public let adapterRatedWatts: Double?
    public let cpuTemperature: Double?
    public let gpuTemperature: Double?

    public init(
        totalWatts: Double?,
        cpuWatts: Double?,
        displayWatts: Double?,
        adapterRatedWatts: Double?,
        cpuTemperature: Double?,
        gpuTemperature: Double?
    ) {
        self.totalWatts = totalWatts
        self.cpuWatts = cpuWatts
        self.displayWatts = displayWatts
        self.adapterRatedWatts = adapterRatedWatts
        self.cpuTemperature = cpuTemperature
        self.gpuTemperature = gpuTemperature
    }
}

public struct SMCAdapterReading: Sendable {
    public let adapterVoltage: Double
    public let adapterCurrent: Double
    public let adapterPower: Double

    public init(
        adapterVoltage: Double,
        adapterCurrent: Double,
        adapterPower: Double
    ) {
        self.adapterVoltage = adapterVoltage
        self.adapterCurrent = adapterCurrent
        self.adapterPower = adapterPower
    }
}

public struct DeviceCapabilities: Sendable {
    public let chargingControl: Bool
    public let adapterControl: Bool
    public let hasMagSafe: Bool
    public let magsafeLEDControl: Bool

    public init(
        chargingControl: Bool,
        adapterControl: Bool,
        hasMagSafe: Bool,
        magsafeLEDControl: Bool
    ) {
        self.chargingControl = chargingControl
        self.adapterControl = adapterControl
        self.hasMagSafe = hasMagSafe
        self.magsafeLEDControl = magsafeLEDControl
    }

    public static func from(
        battery: BatteryCapabilities,
        adapter: AdapterCapabilities
    ) -> DeviceCapabilities {
        DeviceCapabilities(
            chargingControl: battery.inhibitChargeControl,
            adapterControl: battery.forceDischargeControl,
            hasMagSafe: adapter.magSafeControl,
            magsafeLEDControl: adapter.magSafeControl
        )
    }
}
