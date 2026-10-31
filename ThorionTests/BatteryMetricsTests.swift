import Foundation
import Testing

@testable import thorion

@MainActor
struct BatteryMetricsTests {
    @Test func defaultsAreZeroed() {
        let metrics = BatteryMetrics()
        #expect(metrics.batteryPercentage == 0)
        #expect(metrics.isCharging == false)
        #expect(metrics.externalConnected == false)
    }

    @Test func codableRoundTrip() throws {
        var metrics = BatteryMetrics()
        metrics.batteryPercentage = 80
        metrics.cycleCount = 123
        metrics.batteryTemperature = 31.5
        metrics.isCharging = true

        let data = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(BatteryMetrics.self, from: data)
        #expect(decoded == metrics)
    }

    @Test func systemPowerMetricsKeepsOptionalValues() throws {
        let metrics = SystemPowerMetrics(totalWatts: 12.5, cpuWatts: nil)
        let decoded = try JSONDecoder().decode(
            SystemPowerMetrics.self, from: JSONEncoder().encode(metrics))
        #expect(decoded.totalWatts == 12.5)
        #expect(decoded.cpuWatts == nil)
    }

    @Test func powerSourceRoundTrip() throws {
        for source in [PowerSource.battery, .acAdapter, .both] {
            let data = try JSONEncoder().encode(source)
            #expect(try JSONDecoder().decode(PowerSource.self, from: data) == source)
        }
    }
}
