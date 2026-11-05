import ServiceManagement
import Testing

@testable import thorion

@MainActor
struct ChargingHelperRegistrationTests {
    /// The bug: macOS had lost the helper's registration, so every LED command timed out and
    /// the menu could only open Login Items, where there was nothing to allow. macOS 27.2
    /// reported that as `.notFound`, not `.notRegistered`.
    @Test(arguments: [SMAppService.Status.notRegistered, .notFound], [true, false])
    func aHelperMacOSNoLongerKnowsIsRegisteredAgain(status: SMAppService.Status, isResponding: Bool) {
        #expect(ChargingHelperManager.needsRegistration(status: status, isResponding: isResponding))
    }

    /// launchd keeps the registration of an app that was rebuilt or updated but cannot start
    /// the new helper, so commands go unanswered.
    @Test func aRegisteredHelperThatStoppedAnsweringIsRegisteredAgain() {
        #expect(ChargingHelperManager.needsRegistration(status: .enabled, isResponding: false))
    }

    @Test func aWorkingHelperIsLeftAlone() {
        #expect(!ChargingHelperManager.needsRegistration(status: .enabled, isResponding: true))
    }

    /// Registering again would not approve it; the user has to, in Login Items.
    @Test(arguments: [true, false])
    func aHelperWaitingForApprovalIsLeftAlone(isResponding: Bool) {
        #expect(!ChargingHelperManager.needsRegistration(status: .requiresApproval, isResponding: isResponding))
    }
}
