import Testing

@testable import thorion

/// The limit macOS itself enforces, which keeps charging within the app's limit even while the
/// Mac sleeps and Thorion cannot step in.
@MainActor
struct NativeChargeLimitTests {
    private func limit(
        charging: Bool = true,
        chargeLimit: Int = 80,
        displayed: Int = 60,
        hardware: Int = 60,
        usesHardwarePercentage: Bool = false
    ) -> Int {
        NativeChargeLimitService.limit(
            charging: charging,
            chargeLimit: chargeLimit,
            displayedPercentage: displayed,
            hardwarePercentage: hardware,
            usesHardwarePercentage: usesHardwarePercentage
        )
    }

    @Test(arguments: [80, 85, 100])
    func whileChargingMacOSStopsAtTheAppsLimit(chargeLimit: Int) {
        #expect(limit(chargeLimit: chargeLimit) == chargeLimit)
    }

    /// The bug: with "Use hardware percentage" on, macOS was given 100% while charging, so a
    /// Mac that slept charged past the limit. On macOS 27 both percentages read the same.
    @Test func theHardwarePercentageSettingDoesNotLiftTheLimitWhenBothPercentagesAgree() {
        #expect(limit(chargeLimit: 80, displayed: 60, hardware: 60, usesHardwarePercentage: true) == 80)
    }

    /// Where the hardware percentage really differs, macOS cannot know when to stop, so
    /// Thorion pauses charging itself.
    @Test func aDifferentHardwarePercentageLeavesMacOSAt100() {
        #expect(limit(chargeLimit: 80, displayed: 64, hardware: 60, usesHardwarePercentage: true) == 100)
    }

    /// A limit below what macOS accepts is held by cutting the adapter; macOS still stops at 80%.
    @Test func aLimitBelowEightyFallsBackToEighty() {
        #expect(limit(chargeLimit: 50) == 80)
    }

    @Test(arguments: [80, 87, 100])
    func whilePausedMacOSHoldsTheBatteryWhereItIs(displayed: Int) {
        #expect(limit(charging: false, chargeLimit: 80, displayed: displayed, hardware: displayed) == displayed)
    }
}
