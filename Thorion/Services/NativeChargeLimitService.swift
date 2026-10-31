import Defaults
import Foundation
import os.log

enum NativeChargeLimitError: LocalizedError {
    case unavailable
    case requestFailed(operation: String, message: String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The macOS charge limit is not available on this Mac"
        case .requestFailed(let operation, let message):
            "macOS charge limit \(operation) failed: \(message)"
        }
    }
}

/// Pauses charging through the charge limit that macOS itself enforces (System Settings →
/// Battery → Charge Limit).
///
/// macOS 27 removed the SMC charge-inhibit keys (CHTE, CH0C) on Apple Silicon, so writing
/// the SMC can no longer stop charging. powerd still enforces a "max charge limit" (MCL)
/// set through the private PowerUI framework, which is reached through the Objective-C
/// runtime because there is no public header. Verified on an M1 Pro running macOS 27.2:
/// the calls need no privileges, the limit applies to the displayed state of charge,
/// and powerd rejects any limit outside 80...100.
///
/// powerd keeps enforcing the limit while the Mac sleeps, which the SMC path never did.
final class NativeChargeLimitService {
    static let supportedRange = 80...100

    private typealias ErrorPointer = UnsafeMutablePointer<Unmanaged<NSError>?>
    private typealias ReadLimitFunction = @convention(c) (NSObject, Selector, ErrorPointer) -> UInt8
    private typealias WriteLimitFunction = @convention(c) (NSObject, Selector, UInt8, ErrorPointer) -> Bool
    private typealias ReadStateFunction = @convention(c) (NSObject, Selector, ErrorPointer) -> UInt64
    private typealias EnableFunction = @convention(c) (NSObject, Selector, ErrorPointer) -> Bool

    private static let frameworkPath = "/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI"
    private static let clientClassName = "PowerUISmartChargeClient"
    private static let readLimitSelector = NSSelectorFromString("getMCLLimitWithError:")
    private static let writeLimitSelector = NSSelectorFromString("setMCLLimit:error:")
    private static let readEnabledSelector = NSSelectorFromString("isMCLCurrentlyEnabled:")
    private static let enableSelector = NSSelectorFromString("enableMCL:")
    // isMCLCurrentlyEnabled: returns a state rather than a BOOL; 1 is the enabled state.
    private static let enabledState: UInt64 = 1

    private let client: NSObject?
    private let logger = Logger(
        subsystem: "com.thorion.app",
        category: "NativeChargeLimitService"
    )

    init() {
        client = Self.makeClient()
        if client == nil {
            logger.info("macOS charge limit is unavailable")
        }
    }

    var isAvailable: Bool { client != nil }

    /// Stops charging once the displayed state of charge reaches `percentage`. Values
    /// outside `supportedRange` are clamped, because powerd refuses them outright.
    func apply(limit percentage: Int) throws {
        guard let client else { throw NativeChargeLimitError.unavailable }

        let target = min(max(percentage, Self.supportedRange.lowerBound), Self.supportedRange.upperBound)
        if target != percentage {
            logger.debug("Requested limit \(percentage)% is outside what macOS accepts, using \(target)%")
        }

        if target < Self.supportedRange.upperBound {
            let state = try call(client, Self.readEnabledSelector, as: ReadStateFunction.self, operation: "state read") {
                function, selector, errorPointer in function(client, selector, errorPointer)
            }
            if state != Self.enabledState {
                let enabled = try call(client, Self.enableSelector, as: EnableFunction.self, operation: "enable") {
                    function, selector, errorPointer in function(client, selector, errorPointer)
                }
                guard enabled else {
                    throw NativeChargeLimitError.requestFailed(operation: "enable", message: "powerd refused")
                }
                logger.info("Enabled macOS charge limit")
            }
        }

        let current = try call(client, Self.readLimitSelector, as: ReadLimitFunction.self, operation: "read") {
            function, selector, errorPointer in function(client, selector, errorPointer)
        }

        if Int(current) != target {
            let accepted = try call(client, Self.writeLimitSelector, as: WriteLimitFunction.self, operation: "write") {
                function, selector, errorPointer in function(client, selector, UInt8(target), errorPointer)
            }
            guard accepted else {
                throw NativeChargeLimitError.requestFailed(
                    operation: "write",
                    message: "powerd refused \(target)%"
                )
            }
            logger.info("macOS charge limit set to \(target)% (was \(current)%)")
        }

        // Recorded so a later launch only restores a limit Thorion set, instead of
        // overriding one the user chose in System Settings or another app manages.
        Defaults[.nativeChargeLimitApplied] = target < Self.supportedRange.upperBound
    }

    /// Lifts a limit Thorion applied earlier, leaving any other limit untouched.
    func restore() throws {
        guard Defaults[.nativeChargeLimitApplied], isAvailable else { return }
        try apply(limit: Self.supportedRange.upperBound)
    }

    private func call<Function, Result>(
        _ client: NSObject,
        _ selector: Selector,
        as functionType: Function.Type,
        operation: String,
        _ invoke: (Function, Selector, ErrorPointer) -> Result
    ) throws -> Result {
        guard client.responds(to: selector) else {
            throw NativeChargeLimitError.unavailable
        }
        let function = unsafeBitCast(client.method(for: selector), to: functionType)

        return try autoreleasepool {
            var error: Unmanaged<NSError>?
            let result = invoke(function, selector, &error)
            if let error = error?.takeUnretainedValue() {
                throw NativeChargeLimitError.requestFailed(
                    operation: operation,
                    message: error.localizedDescription
                )
            }
            return result
        }
    }

    private static func makeClient() -> NSObject? {
        guard dlopen(frameworkPath, RTLD_NOW) != nil,
            let clientClass = NSClassFromString(clientClassName) as? NSObject.Type
        else {
            return nil
        }

        // alloc and initWithClientName: go through perform so their +1 results are
        // balanced by hand: init consumes the allocated object and returns an owned one.
        let initializer = NSSelectorFromString("initWithClientName:")
        guard clientClass.instancesRespond(to: initializer),
            let allocated = clientClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
                as? NSObject,
            let client = allocated.perform(initializer, with: "Thorion")?.takeRetainedValue() as? NSObject
        else {
            return nil
        }

        let requiredSelectors = [readLimitSelector, writeLimitSelector, readEnabledSelector, enableSelector]
        guard requiredSelectors.allSatisfy({ client.responds(to: $0) }) else { return nil }

        return client
    }
}
