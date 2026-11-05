import Foundation

/// Works out what charging should do for one battery reading: whether to charge, whether
/// the Mac should run on the adapter, and what the MagSafe LED should say.
///
/// It touches neither IOKit, the helper nor Defaults, so every rule can be checked by a
/// unit test. `ChargeManager` gathers the inputs and carries out the result.
struct ChargePolicy {
    struct Settings: Equatable {
        /// The limit the user asked for, or 100 while Top Up is on.
        var chargeLimit: Int
        var sailingMode: Bool
        var sailingModeLimit: Int
        var automaticDischarge: Bool
        var heatProtection: Bool
        var heatProtectionLimit: Int
        var forceDischarge: Bool
        /// The lowest battery level at which this Mac can hold charging paused (see
        /// `ChargeLimitScale.lowestHoldablePercentage`). Below it, macOS keeps charging whatever
        /// Thorion asks, so heat protection cannot pause there, and a limit under it is raised
        /// to it unless the battery can be held another way (see `canCutAdapter`).
        var lowestHoldablePercentage = 0
        /// Whether the adapter can really be cut: the Mac supports it and the helper that does
        /// it is working. Together with Automatic discharge this lets a limit below
        /// `lowestHoldablePercentage` be held by running the Mac on its battery between charges.
        var canCutAdapter = false
    }

    /// What the MagSafe LED should say. `ChargeManager` turns it into an LED color.
    enum Indicator: Equatable {
        /// Orange.
        case charging
        /// Green: the battery is being left alone, on the adapter or held on its battery.
        case paused
        /// Slow blinking orange: the adapter is connected but the Mac is draining the battery.
        case runningOnBattery
        /// The color the user picked for heat protection.
        case heatProtection
    }

    struct Decision: Equatable {
        var charging: Bool
        var adapterEnabled: Bool
        var indicator: Indicator
        var reason: String
        var isSailing: Bool
        /// The limit actually held, which can be higher than the one asked for.
        var chargeLimit: Int
    }

    /// Cutting and restoring the adapter renegotiates power each time, so a battery held that
    /// way floats inside at least this range instead of being topped up at every percent.
    static let minimumFloatRange = 2

    /// Set once the battery reaches the limit and cleared when charging has to start again.
    /// Sailing mode only keeps charging paused inside its range after this is set, so
    /// plugging in below the limit always charges up to it first.
    private var hasReachedChargeLimit = false
    private var lastChargeLimit: Int?

    /// Forgets that the limit was reached, as happens whenever the adapter is plugged in
    /// or out or charge management is switched on.
    mutating func reset() {
        hasReachedChargeLimit = false
    }

    mutating func decide(percentage: Int, temperature: Double, settings: Settings) -> Decision {
        // A limit below what macOS can hold is held by cutting the adapter when that is allowed
        // (Automatic discharge) and possible, rather than being raised to what macOS can hold.
        let cutsAdapterToHold = settings.automaticDischarge
            && settings.canCutAdapter
            && settings.chargeLimit < settings.lowestHoldablePercentage
        let limit = cutsAdapterToHold
            ? settings.chargeLimit
            : max(settings.chargeLimit, settings.lowestHoldablePercentage)

        // A battery held by cutting the adapter always floats inside a range, sailing mode or not.
        let floats = settings.sailingMode || cutsAdapterToHold
        let range = cutsAdapterToHold
            ? max(settings.sailingModeLimit, Self.minimumFloatRange)
            : settings.sailingModeLimit

        // Raising the limit means "charge up to the new limit", even when the battery
        // already sits within the sailing range below it.
        if let lastChargeLimit, limit > lastChargeLimit {
            hasReachedChargeLimit = false
        }
        lastChargeLimit = limit

        var charging: Bool
        var adapterEnabled: Bool
        var holdsByCuttingAdapter = false
        var reason: String

        if percentage > limit {
            hasReachedChargeLimit = true
            charging = false
            adapterEnabled = !settings.automaticDischarge
            reason = "Battery is above the charge limit of \(limit)%"
        } else if percentage == limit {
            hasReachedChargeLimit = true
            charging = false
            adapterEnabled = !cutsAdapterToHold
            holdsByCuttingAdapter = cutsAdapterToHold
            reason = "Battery has reached the charge limit of \(limit)%"
        } else if floats {
            let sailingThreshold = limit - range
            let inSailingRange = percentage >= sailingThreshold

            if inSailingRange && hasReachedChargeLimit {
                charging = false
                adapterEnabled = !cutsAdapterToHold
                holdsByCuttingAdapter = cutsAdapterToHold
                reason = "Sailing mode is maintaining charge below \(limit)%"
            } else {
                let droppedOutOfSailingRange = !inSailingRange && hasReachedChargeLimit
                hasReachedChargeLimit = false
                charging = true
                adapterEnabled = true
                if inSailingRange {
                    reason = "Charging to reach charge limit of \(limit)%"
                } else if droppedOutOfSailingRange {
                    reason = "Battery dropped below sailing threshold of \(sailingThreshold)%"
                } else {
                    reason = "Battery is below the charge limit of \(limit)%"
                }
            }
        } else {
            charging = true
            adapterEnabled = true
            reason = "Battery is below the charge limit of \(limit)%"
        }

        // Heat only matters while the battery would otherwise be charging. At or above the
        // limit charging is already paused, and the LED must keep saying so (green), not
        // switch to the heat protection color.
        let heatProtectionPausesCharging = charging
            && settings.heatProtection
            && temperature > Double(settings.heatProtectionLimit)
            && percentage >= settings.lowestHoldablePercentage
        if heatProtectionPausesCharging {
            charging = false
            reason = "Battery temperature exceeds \(settings.heatProtectionLimit)°C"
        }

        if settings.forceDischarge {
            charging = false
            adapterEnabled = false
            holdsByCuttingAdapter = false
        }

        let isSailing = floats && hasReachedChargeLimit && !settings.forceDischarge
            && percentage <= limit
            && percentage >= limit - range

        let indicator: Indicator
        if !adapterEnabled && !holdsByCuttingAdapter {
            indicator = .runningOnBattery
        } else if heatProtectionPausesCharging {
            indicator = .heatProtection
        } else if charging {
            indicator = .charging
        } else {
            indicator = .paused
        }

        return Decision(
            charging: charging,
            adapterEnabled: adapterEnabled,
            indicator: indicator,
            reason: reason,
            isSailing: isSailing,
            chargeLimit: limit
        )
    }
}
