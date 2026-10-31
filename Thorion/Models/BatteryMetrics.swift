import Foundation

struct BatteryMetrics: Codable, Equatable {
    var batteryPercentage: Int = 0
    var hardwareBatteryPercentage: Int = 0
    var isCharging: Bool = false
    var timeRemaining: Int = 0

    var batteryVoltage: Double = 0
    var batteryCurrent: Double = 0
    var batteryPower: Double = 0
    var batteryTemperature: Double = 0

    var batteryHealth: Int = 0
    var cycleCount: Int = 0

    var currentCapacity: Int = 0
    var maxCapacity: Int = 0
    var designCapacity: Int = 0

    var externalConnected: Bool = false
}

struct BatteryHistorySample: Identifiable, Equatable {
    let date: Date
    let batteryPercentage: Int
    let hardwareBatteryPercentage: Int
    let temperature: Double?

    var id: Date { date }
}

struct AdapterMetrics: Equatable {
    var adapterConnected: Bool = false
    var adapterVoltage: Double = 0
    var adapterCurrent: Double = 0
    var adapterPower: Double = 0
}

struct SystemPowerMetrics: Codable, Equatable {
    var totalWatts: Double?
    var cpuWatts: Double?
    var displayWatts: Double?
    var adapterRatedWatts: Double?
    var cpuTemperature: Double?
    var gpuTemperature: Double?

    init(
        totalWatts: Double? = nil,
        cpuWatts: Double? = nil,
        displayWatts: Double? = nil,
        adapterRatedWatts: Double? = nil,
        cpuTemperature: Double? = nil,
        gpuTemperature: Double? = nil
    ) {
        self.totalWatts = totalWatts
        self.cpuWatts = cpuWatts
        self.displayWatts = displayWatts
        self.adapterRatedWatts = adapterRatedWatts
        self.cpuTemperature = cpuTemperature
        self.gpuTemperature = gpuTemperature
    }
}

struct BatteryControlState: Equatable {
    var batteryPercentage: Int = 0
    var hardwareBatteryPercentage: Int = 0
    var adapterConnected: Bool = false
    var batteryTemperature: Double = 0
}
