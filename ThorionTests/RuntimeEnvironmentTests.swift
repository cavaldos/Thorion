import Testing

@testable import thorion

@MainActor
struct RuntimeEnvironmentTests {
    /// The whole point: the app skips its startup only if it can tell it is a test host.
    /// When this fails, the app terminates itself on machines without a battery (such as
    /// CI runners) before the tests can connect.
    @Test func theTestHostRecognisesItself() {
        #expect(RuntimeEnvironment.isRunningTests)
    }

    @Test(arguments: [
        "XCTestConfigurationFilePath",
        "XCTestBundlePath",
        "XCTestSessionIdentifier",
    ])
    func recognisesTheVariablesSetByTheTestRunner(key: String) {
        #expect(RuntimeEnvironment.isRunningTests(in: [key: "/tmp/value"]))
    }

    @Test func aNormalLaunchIsNotATestRun() {
        #expect(!RuntimeEnvironment.isRunningTests(in: [:]))
        #expect(!RuntimeEnvironment.isRunningTests(in: ["HOME": "/Users/someone", "PATH": "/usr/bin"]))
    }
}
