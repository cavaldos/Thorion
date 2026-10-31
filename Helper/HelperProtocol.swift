import Foundation
import smc_power

@objc protocol HelperProtocol {
    func readBatteryMetrics(
        reply: @escaping @Sendable (Double, Double, Double) -> Void)
    func readAdapterMetrics(
        reply: @escaping @Sendable (Double, Double, Double) -> Void
    )
    // NSNumber rather than Double? because HelperProtocol is an @objc protocol
    // (required by NSXPCInterface) and optional Doubles are not representable in
    // Objective-C. NSNumber bridges to nil, so unsupported stays distinguishable
    // from a genuine zero.
    // Order: total, CPU, display, adapter rated watts, CPU temperature, GPU temperature.
    func readSystemPower(
        reply: @escaping @Sendable (
            NSNumber?, NSNumber?, NSNumber?, NSNumber?, NSNumber?, NSNumber?
        ) -> Void)
    func getCapabilities(
        reply: @escaping @Sendable (Bool, Bool, Bool, Bool) -> Void)
}
