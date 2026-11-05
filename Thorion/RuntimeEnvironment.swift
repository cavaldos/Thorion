import Foundation

enum RuntimeEnvironment {
    /// True while this process is the host of a unit-test bundle (`xcodebuild test`, ⌘U).
    static var isRunningTests: Bool {
        isRunningTests(in: ProcessInfo.processInfo.environment)
    }

    /// Takes the environment as a parameter so the check can be tested with made-up ones.
    static func isRunningTests(in environment: [String: String]) -> Bool {
        let testRunnerKeys = [
            "XCTestConfigurationFilePath",
            "XCTestBundlePath",
            "XCTestSessionIdentifier",
        ]
        return testRunnerKeys.contains { environment[$0] != nil }
    }
}
