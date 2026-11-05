import Testing

@testable import thorion

@MainActor
struct ChargeLimitScaleTests {
    @Test func macOSChargeLimitCannotHoldTheBatteryBelowEightyPercent() {
        #expect(ChargeLimitScale.lowestHoldablePercentage(usingNativeChargeLimit: true) == 80)
        #expect(ChargeLimitScale.lowestHoldablePercentage(usingNativeChargeLimit: false) == 0)
    }

    @Test(arguments: [
        (chosen: 70, native: true, expected: 80),
        (chosen: 80, native: true, expected: 80),
        (chosen: 90, native: true, expected: 90),
        (chosen: 70, native: false, expected: 70),
        (chosen: 50, native: false, expected: 50),
    ])
    func aLimitChosenBelowWhatCanBeHeldIsHeldAtThatLevel(chosen: Int, native: Bool, expected: Int) {
        #expect(ChargeLimitScale.effectiveLimit(chosen, usingNativeChargeLimit: native) == expected)
    }

    @Test(arguments: [
        (chosen: 50, native: true, raised: true),
        (chosen: 70, native: true, raised: true),
        (chosen: 75, native: true, raised: true),
        (chosen: 80, native: true, raised: false),
        (chosen: 100, native: true, raised: false),
        (chosen: 50, native: false, raised: false),
        (chosen: 70, native: false, raised: false),
    ])
    func saysWhenTheLimitChosenIsNotTheOneHeld(chosen: Int, native: Bool, raised: Bool) {
        #expect(ChargeLimitScale.isRaised(chosen, usingNativeChargeLimit: native) == raised)
    }

    /// Regression: the slider was stopped at 80% on Macs that use the macOS charge limit,
    /// so with the battery at 74% the limit could not be dragged below the battery level.
    /// Any limit in 50...100 can be chosen; what is held instead is told apart on screen.
    @Test(arguments: [
        (position: 62.0, expected: 60),
        (position: 70.0, expected: 70),
        (position: 74.0, expected: 75),
        (position: 10.0, expected: 50),
        (position: 130.0, expected: 100),
    ])
    func draggingSnapsToTheStepAndCanGoBelowTheBatteryLevel(position: Double, expected: Int) {
        #expect(ChargeLimitScale.snapped(position) == expected)
    }

    @Test(arguments: [
        (automaticDischarge: true, canCutAdapter: true, expected: true),
        (automaticDischarge: true, canCutAdapter: false, expected: false),
        (automaticDischarge: false, canCutAdapter: true, expected: false),
        (automaticDischarge: false, canCutAdapter: false, expected: false),
    ])
    func theBatteryIsHeldByCuttingTheAdapterOnlyWithOptInAndAWorkingHelper(
        automaticDischarge: Bool, canCutAdapter: Bool, expected: Bool
    ) {
        #expect(
            ChargeLimitScale.holdsByCuttingAdapter(
                automaticDischarge: automaticDischarge, canCutAdapter: canCutAdapter) == expected)
    }

    @Test func cuttingTheAdapterKeepsALimitBelowWhatMacOSCanHold() {
        #expect(
            ChargeLimitScale.effectiveLimit(
                70, usingNativeChargeLimit: true, holdsByCuttingAdapter: true) == 70)
        #expect(
            !ChargeLimitScale.isRaised(
                70, usingNativeChargeLimit: true, holdsByCuttingAdapter: true))
        #expect(
            ChargeLimitScale.isHeldByCuttingAdapter(
                70, usingNativeChargeLimit: true, holdsByCuttingAdapter: true))
    }

    @Test func nothingIsHeldByCuttingTheAdapterWhenMacOSCanHoldTheLimit() {
        #expect(
            !ChargeLimitScale.isHeldByCuttingAdapter(
                85, usingNativeChargeLimit: true, holdsByCuttingAdapter: true))
        #expect(
            !ChargeLimitScale.isHeldByCuttingAdapter(
                70, usingNativeChargeLimit: false, holdsByCuttingAdapter: true))
        #expect(
            !ChargeLimitScale.isHeldByCuttingAdapter(
                70, usingNativeChargeLimit: true, holdsByCuttingAdapter: false))
    }
}
