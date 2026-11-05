import Testing

@testable import thorion

/// The charging rules, written the way they are described to the user:
/// below the limit charge (orange LED), at or above it don't (green LED).
@MainActor
struct ChargePolicyTests {
    /// The setup from the bug report: a limit of 70% with sailing mode on, as it is by default.
    private func settings(
        limit: Int = 70,
        sailingMode: Bool = true,
        sailingRange: Int = 5,
        automaticDischarge: Bool = false,
        heatProtection: Bool = false,
        heatLimit: Int = 40,
        forceDischarge: Bool = false,
        lowestHoldable: Int = 0,
        canCutAdapter: Bool = false
    ) -> ChargePolicy.Settings {
        ChargePolicy.Settings(
            chargeLimit: limit,
            sailingMode: sailingMode,
            sailingModeLimit: sailingRange,
            automaticDischarge: automaticDischarge,
            heatProtection: heatProtection,
            heatProtectionLimit: heatLimit,
            forceDischarge: forceDischarge,
            lowestHoldablePercentage: lowestHoldable,
            canCutAdapter: canCutAdapter
        )
    }

    /// A Mac that can only pause charging from 80%, with Automatic discharge on and an adapter
    /// that can be cut: a limit of 70% is held by running the Mac on its battery.
    private func cuttingTheAdapter(
        limit: Int = 70,
        sailingMode: Bool = true,
        sailingRange: Int = 5,
        forceDischarge: Bool = false
    ) -> ChargePolicy.Settings {
        settings(
            limit: limit, sailingMode: sailingMode, sailingRange: sailingRange,
            automaticDischarge: true, forceDischarge: forceDischarge,
            lowestHoldable: 80, canCutAdapter: true)
    }

    // MARK: Plugging in below the limit

    @Test(arguments: [10, 50, 64, 65, 66, 67, 69])
    func pluggingInBelowTheLimitChargesWithTheOrangeLED(percentage: Int) {
        var policy = ChargePolicy()
        let decision = policy.decide(percentage: percentage, temperature: 30, settings: settings())

        #expect(decision.charging)
        #expect(decision.adapterEnabled)
        #expect(decision.indicator == .charging)
    }

    @Test func chargingStopsAtTheLimitWithTheGreenLED() {
        var policy = ChargePolicy()
        let settings = settings()
        for percentage in 60...69 {
            #expect(policy.decide(percentage: percentage, temperature: 30, settings: settings).charging)
        }

        let decision = policy.decide(percentage: 70, temperature: 30, settings: settings)
        #expect(!decision.charging)
        #expect(decision.adapterEnabled)
        #expect(decision.indicator == .paused)
    }

    @Test(arguments: [71, 75, 85, 100])
    func aboveTheLimitDoesNotChargeAndTheLEDIsGreen(percentage: Int) {
        var policy = ChargePolicy()
        let decision = policy.decide(percentage: percentage, temperature: 30, settings: settings())

        #expect(!decision.charging)
        #expect(decision.adapterEnabled)
        #expect(decision.indicator == .paused)
    }

    @Test func automaticDischargeAboveTheLimitRunsOnBattery() {
        var policy = ChargePolicy()
        let decision = policy.decide(
            percentage: 85, temperature: 30, settings: settings(automaticDischarge: true))

        #expect(!decision.charging)
        #expect(!decision.adapterEnabled)
        #expect(decision.indicator == .runningOnBattery)
    }

    // MARK: Sailing mode

    @Test func sailingHoldsTheBatteryOnlyAfterTheLimitWasReached() {
        var policy = ChargePolicy()
        let settings = settings()

        // Charge up to the limit first, however close to it the battery starts.
        #expect(policy.decide(percentage: 68, temperature: 30, settings: settings).charging)
        #expect(!policy.decide(percentage: 70, temperature: 30, settings: settings).charging)

        // Then float inside the range (65...70) without charging.
        for percentage in [69, 67, 65] {
            let decision = policy.decide(percentage: percentage, temperature: 30, settings: settings)
            #expect(!decision.charging)
            #expect(decision.indicator == .paused)
            #expect(decision.isSailing)
        }

        // Dropping below the range starts charging again, all the way back to the limit.
        for percentage in [64, 66, 69] {
            let decision = policy.decide(percentage: percentage, temperature: 30, settings: settings)
            #expect(decision.charging)
            #expect(decision.indicator == .charging)
        }
        #expect(!policy.decide(percentage: 70, temperature: 30, settings: settings).charging)
    }

    @Test func withoutSailingChargingResumesAsSoonAsTheBatteryDropsBelowTheLimit() {
        var policy = ChargePolicy()
        let settings = settings(sailingMode: false)

        #expect(!policy.decide(percentage: 70, temperature: 30, settings: settings).charging)
        let decision = policy.decide(percentage: 69, temperature: 30, settings: settings)
        #expect(decision.charging)
        #expect(!decision.isSailing)
    }

    @Test func raisingTheLimitChargesEvenInsideTheSailingRange() {
        var policy = ChargePolicy()
        #expect(!policy.decide(percentage: 70, temperature: 30, settings: settings(limit: 70)).charging)
        #expect(!policy.decide(percentage: 68, temperature: 30, settings: settings(limit: 70)).charging)

        let decision = policy.decide(percentage: 68, temperature: 30, settings: settings(limit: 80))
        #expect(decision.charging)
        #expect(decision.indicator == .charging)
    }

    @Test func pluggingInAgainForgetsThatTheLimitWasReached() {
        var policy = ChargePolicy()
        #expect(!policy.decide(percentage: 70, temperature: 30, settings: settings()).charging)
        #expect(!policy.decide(percentage: 68, temperature: 30, settings: settings()).charging)

        // The adapter was unplugged and plugged in again, which resets the policy.
        policy.reset()
        #expect(policy.decide(percentage: 68, temperature: 30, settings: settings()).charging)
    }

    // MARK: Heat protection

    @Test func heatProtectionPausesChargingBelowTheLimit() {
        var policy = ChargePolicy()
        let decision = policy.decide(
            percentage: 50, temperature: 41, settings: settings(heatProtection: true))

        #expect(!decision.charging)
        #expect(decision.adapterEnabled)
        #expect(decision.indicator == .heatProtection)
        #expect(decision.reason.contains("temperature"))
    }

    @Test(arguments: [70, 85])
    func heatProtectionDoesNotTurnTheLEDAwayFromGreenAtOrAboveTheLimit(percentage: Int) {
        var policy = ChargePolicy()
        let decision = policy.decide(
            percentage: percentage, temperature: 45, settings: settings(heatProtection: true))

        #expect(!decision.charging)
        #expect(decision.indicator == .paused)
        #expect(!decision.reason.contains("temperature"))
    }

    @Test(arguments: [
        (heatProtection: false, temperature: 60.0),
        (heatProtection: true, temperature: 40.0),
        (heatProtection: true, temperature: 0.0),
    ])
    func heatProtectionStaysOutOfTheWayUnlessTheBatteryIsTooHot(
        heatProtection: Bool, temperature: Double
    ) {
        var policy = ChargePolicy()
        let decision = policy.decide(
            percentage: 50, temperature: temperature,
            settings: settings(heatProtection: heatProtection, heatLimit: 40))

        #expect(decision.charging)
        #expect(decision.indicator == .charging)
    }

    // MARK: Force discharge

    @Test func dischargeRunsOnBattery() {
        var policy = ChargePolicy()
        let decision = policy.decide(
            percentage: 85, temperature: 30, settings: settings(forceDischarge: true))

        #expect(!decision.charging)
        #expect(!decision.adapterEnabled)
        #expect(decision.indicator == .runningOnBattery)
    }

    // MARK: Top Up

    @Test func topUpChargesAllTheWayToFull() {
        var policy = ChargePolicy()
        #expect(policy.decide(percentage: 85, temperature: 30, settings: settings(limit: 100)).charging)
        #expect(!policy.decide(percentage: 100, temperature: 30, settings: settings(limit: 100)).charging)
    }

    // MARK: Macs that can only pause charging from 80%

    @Test func aLimitBelowWhatMacOSCanHoldIsRaisedToIt() {
        var policy = ChargePolicy()
        let settings = settings(limit: 70, lowestHoldable: 80)

        // macOS keeps charging up to 80% whatever Thorion asks, so Thorion says so
        // (orange LED) instead of claiming that charging is paused at 70%.
        for percentage in [60, 70, 75, 79] {
            let decision = policy.decide(percentage: percentage, temperature: 30, settings: settings)
            #expect(decision.charging)
            #expect(decision.indicator == .charging)
            #expect(decision.chargeLimit == 80)
        }

        let atTheFloor = policy.decide(percentage: 80, temperature: 30, settings: settings)
        #expect(!atTheFloor.charging)
        #expect(atTheFloor.indicator == .paused)

        let above = policy.decide(percentage: 85, temperature: 30, settings: settings)
        #expect(!above.charging)
        #expect(above.indicator == .paused)
    }

    @Test func aLimitAtOrAboveWhatMacOSCanHoldIsLeftAlone() {
        var policy = ChargePolicy()
        let decision = policy.decide(
            percentage: 85, temperature: 30, settings: settings(limit: 90, lowestHoldable: 80))

        #expect(decision.chargeLimit == 90)
        #expect(decision.charging)
    }

    @Test func heatProtectionCannotPauseWhereMacOSWouldKeepCharging() {
        var policy = ChargePolicy()
        let settings = settings(limit: 100, heatProtection: true, lowestHoldable: 80)

        let low = policy.decide(percentage: 60, temperature: 45, settings: settings)
        #expect(low.charging)
        #expect(low.indicator == .charging)

        let high = policy.decide(percentage: 90, temperature: 45, settings: settings)
        #expect(!high.charging)
        #expect(high.indicator == .heatProtection)
    }

    // MARK: Limits below what macOS can hold, held by cutting the adapter

    @Test func aboveTheLimitTheBatteryDrainsDownToIt() {
        var policy = ChargePolicy()
        let decision = policy.decide(percentage: 74, temperature: 30, settings: cuttingTheAdapter())

        #expect(!decision.charging)
        #expect(!decision.adapterEnabled)
        #expect(decision.indicator == .runningOnBattery)
        #expect(decision.chargeLimit == 70)
    }

    @Test func atTheLimitTheAdapterStaysCutAndTheLEDIsGreen() {
        var policy = ChargePolicy()
        let decision = policy.decide(percentage: 70, temperature: 30, settings: cuttingTheAdapter())

        #expect(!decision.charging)
        #expect(!decision.adapterEnabled)
        #expect(decision.indicator == .paused)
        #expect(decision.isSailing)
    }

    @Test func theBatteryThenFloatsInsideTheRangeOnItsBattery() {
        var policy = ChargePolicy()
        let settings = cuttingTheAdapter()
        _ = policy.decide(percentage: 70, temperature: 30, settings: settings)

        for percentage in [69, 67, 65] {
            let decision = policy.decide(percentage: percentage, temperature: 30, settings: settings)
            #expect(!decision.charging)
            #expect(!decision.adapterEnabled)
            #expect(decision.indicator == .paused)
        }
    }

    @Test func belowTheRangeTheAdapterComesBackAndChargesUpToTheLimit() {
        var policy = ChargePolicy()
        let settings = cuttingTheAdapter()
        _ = policy.decide(percentage: 70, temperature: 30, settings: settings)
        _ = policy.decide(percentage: 65, temperature: 30, settings: settings)

        for percentage in [64, 66, 69] {
            let decision = policy.decide(percentage: percentage, temperature: 30, settings: settings)
            #expect(decision.charging)
            #expect(decision.adapterEnabled)
            #expect(decision.indicator == .charging)
        }

        let atTheLimit = policy.decide(percentage: 70, temperature: 30, settings: settings)
        #expect(!atTheLimit.adapterEnabled)
        #expect(atTheLimit.indicator == .paused)
    }

    @Test func pluggingInBelowTheLimitStillChargesFirst() {
        var policy = ChargePolicy()
        let decision = policy.decide(percentage: 67, temperature: 30, settings: cuttingTheAdapter())

        #expect(decision.charging)
        #expect(decision.adapterEnabled)
        #expect(decision.indicator == .charging)
    }

    /// Cutting the adapter renegotiates power each time, so it must not happen at every percent.
    @Test func theBatteryFloatsEvenWithSailingModeOff() {
        var policy = ChargePolicy()
        let settings = cuttingTheAdapter(sailingMode: false, sailingRange: 1)
        _ = policy.decide(percentage: 70, temperature: 30, settings: settings)

        for percentage in [69, 68] {
            let decision = policy.decide(percentage: percentage, temperature: 30, settings: settings)
            #expect(!decision.adapterEnabled)
            #expect(!decision.charging)
        }

        let below = policy.decide(percentage: 67, temperature: 30, settings: settings)
        #expect(below.charging)
        #expect(below.adapterEnabled)
    }

    @Test func withoutAutomaticDischargeTheLimitIsRaisedInsteadAndTheAdapterIsLeftAlone() {
        var policy = ChargePolicy()
        let settings = settings(
            limit: 70, automaticDischarge: false, lowestHoldable: 80, canCutAdapter: true)
        let decision = policy.decide(percentage: 74, temperature: 30, settings: settings)

        #expect(decision.charging)
        #expect(decision.adapterEnabled)
        #expect(decision.chargeLimit == 80)
    }

    @Test func withoutAnAdapterThatCanBeCutTheLimitIsRaisedInstead() {
        var policy = ChargePolicy()
        let settings = settings(
            limit: 70, automaticDischarge: true, lowestHoldable: 80, canCutAdapter: false)
        let decision = policy.decide(percentage: 74, temperature: 30, settings: settings)

        #expect(decision.charging)
        #expect(decision.adapterEnabled)
        #expect(decision.chargeLimit == 80)
    }

    @Test func aLimitMacOSCanHoldIsStillHeldByMacOS() {
        var policy = ChargePolicy()
        let decision = policy.decide(
            percentage: 85, temperature: 30, settings: cuttingTheAdapter(limit: 85))

        #expect(!decision.charging)
        #expect(decision.adapterEnabled)
        #expect(decision.indicator == .paused)
    }

    @Test func topUpStillChargesToFull() {
        var policy = ChargePolicy()
        let decision = policy.decide(
            percentage: 74, temperature: 30, settings: cuttingTheAdapter(limit: 100))

        #expect(decision.charging)
        #expect(decision.adapterEnabled)
    }

    @Test func theDischargeButtonStillRunsOnBatteryWhileHolding() {
        var policy = ChargePolicy()
        let decision = policy.decide(
            percentage: 70, temperature: 30, settings: cuttingTheAdapter(forceDischarge: true))

        #expect(!decision.adapterEnabled)
        #expect(decision.indicator == .runningOnBattery)
    }
}
