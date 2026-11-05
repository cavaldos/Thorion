import ServiceManagement
import Testing

@testable import thorion

@MainActor
struct LaunchAtLoginSuggestionTests {
    @Test func suggestsWhenThorionIsNotALoginItem() {
        #expect(LaunchAtLoginSuggestion.shouldSuggest(status: .notRegistered, skipped: false))
    }

    @Test(arguments: [
        SMAppService.Status.enabled,
        .requiresApproval,
        .notFound,
    ])
    func staysQuietWhenThereIsNothingToSuggest(status: SMAppService.Status) {
        #expect(!LaunchAtLoginSuggestion.shouldSuggest(status: status, skipped: false))
    }

    @Test(arguments: [
        SMAppService.Status.notRegistered,
        .enabled,
        .requiresApproval,
        .notFound,
    ])
    func neverAsksAgainOnceTheUserOptedOut(status: SMAppService.Status) {
        #expect(!LaunchAtLoginSuggestion.shouldSuggest(status: status, skipped: true))
    }
}
