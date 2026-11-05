import Testing
import smc_power

@testable import thorion

/// The MagSafe LED: orange only while the battery charges, green once it is at or above the
/// limit or full.
@MainActor
struct MagSafeLEDTests {
    private func settings(
        limit: Int = 85,
        automaticDischarge: Bool = false,
        forceDischarge: Bool = false,
        lowestHoldable: Int = 0,
        canCutAdapter: Bool = false
    ) -> ChargePolicy.Settings {
        ChargePolicy.Settings(
            chargeLimit: limit,
            sailingMode: true,
            sailingModeLimit: 5,
            automaticDischarge: automaticDischarge,
            heatProtection: false,
            heatProtectionLimit: 40,
            forceDischarge: forceDischarge,
            lowestHoldablePercentage: lowestHoldable,
            canCutAdapter: canCutAdapter
        )
    }

    private func led(_ decision: ChargePolicy.Decision) -> MagSafeLEDState {
        decision.indicator.ledState(heatProtection: .off)
    }

    @Test func chargingIsOrange() {
        #expect(ChargePolicy.Indicator.charging.ledState(heatProtection: .off) == .orange)
    }

    @Test(arguments: [ChargePolicy.Indicator.paused, .runningOnBattery])
    func notChargingAtOrAboveTheLimitIsGreen(indicator: ChargePolicy.Indicator) {
        #expect(indicator.ledState(heatProtection: .off) == .green)
    }

    @Test(arguments: [
        MagSafeLEDState.off, .green, .orange, .blinkOrangeSlow, .blinkOrangeFast,
    ])
    func heatProtectionShowsTheColorTheUserPicked(color: MagSafeLEDState) {
        #expect(ChargePolicy.Indicator.heatProtection.ledState(heatProtection: color) == color)
    }

    @Test func orangeWhileChargingUpToTheLimitThenGreen() {
        var policy = ChargePolicy()
        let settings = settings()

        for percentage in 60...84 {
            #expect(led(policy.decide(percentage: percentage, temperature: 0, settings: settings)) == .orange)
        }
        #expect(led(policy.decide(percentage: 85, temperature: 0, settings: settings)) == .green)
    }

    @Test(arguments: [86, 95, 100])
    func pluggedInAboveTheLimitIsGreen(percentage: Int) {
        var policy = ChargePolicy()
        #expect(led(policy.decide(percentage: percentage, temperature: 0, settings: settings())) == .green)
    }

    /// Top Up (a limit of 100%) charges in orange and turns green once the battery is full.
    @Test func topUpIsOrangeUntilFullThenGreen() {
        var policy = ChargePolicy()
        let topUp = settings(limit: 100)

        #expect(led(policy.decide(percentage: 90, temperature: 0, settings: topUp)) == .orange)
        #expect(led(policy.decide(percentage: 99, temperature: 0, settings: topUp)) == .orange)
        #expect(led(policy.decide(percentage: 100, temperature: 0, settings: topUp)) == .green)
    }

    /// Sailing keeps charging paused after the limit was reached, so the LED stays green.
    @Test func sailingBelowTheLimitStaysGreen() {
        var policy = ChargePolicy()
        let settings = settings()
        _ = policy.decide(percentage: 85, temperature: 0, settings: settings)

        for percentage in [84, 82, 80] {
            #expect(led(policy.decide(percentage: percentage, temperature: 0, settings: settings)) == .green)
        }
        #expect(led(policy.decide(percentage: 79, temperature: 0, settings: settings)) == .orange)
    }

    /// The bug report: dragging the limit below the battery with Automatic discharge on left
    /// the LED blinking orange while the Mac drained the battery. The limit is reached, so green.
    @Test(arguments: [98, 87])
    func automaticDischargeAboveTheLimitIsGreen(percentage: Int) {
        var policy = ChargePolicy()
        let settings = settings(limit: 80, automaticDischarge: true, lowestHoldable: 80)

        let decision = policy.decide(percentage: percentage, temperature: 0, settings: settings)
        #expect(!decision.adapterEnabled)
        #expect(led(decision) == .green)
    }

    /// The example from the bug report, on a Mac that can only pause charging from 80%: the
    /// battery at 60% and the limit dragged to 50%. With the helper able to cut the adapter,
    /// the Mac drains to 50% and holds there, green all the way.
    @Test func batteryAtSixtyWithTheLimitDraggedToFiftyIsGreen() {
        var policy = ChargePolicy()
        let settings = settings(limit: 50, automaticDischarge: true, lowestHoldable: 80, canCutAdapter: true)

        for percentage in [60, 55, 51, 50] {
            #expect(led(policy.decide(percentage: percentage, temperature: 0, settings: settings)) == .green)
        }
    }

    /// Without a helper that can cut the adapter, macOS keeps charging up to 80% whatever
    /// Thorion asks, so the LED stays honest and orange.
    @Test func withoutAWorkingHelperMacOSChargesToEightyInOrange() {
        var policy = ChargePolicy()
        let settings = settings(limit: 50, automaticDischarge: true, lowestHoldable: 80, canCutAdapter: false)

        let decision = policy.decide(percentage: 60, temperature: 0, settings: settings)
        #expect(decision.charging)
        #expect(decision.chargeLimit == 80)
        #expect(led(decision) == .orange)
    }

    @Test func theDischargeButtonIsGreenToo() {
        var policy = ChargePolicy()
        let decision = policy.decide(percentage: 90, temperature: 0, settings: settings(forceDischarge: true))

        #expect(!decision.adapterEnabled)
        #expect(led(decision) == .green)
    }
}
