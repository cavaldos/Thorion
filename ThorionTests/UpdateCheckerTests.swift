import Testing

@testable import thorion

@MainActor
struct UpdateCheckerTests {
    @Test(arguments: [("v1.2.3", "1.2.3"), ("1.2.3", "1.2.3"), ("v", ""), ("", "")])
    func normalizesTag(tag: String, expected: String) {
        #expect(UpdateChecker.normalizedVersion(tag) == expected)
    }

    @Test(arguments: [
        ("0.3.0", "0.2.9", true),
        ("1.0.0", "0.9.9", true),
        ("0.2.10", "0.2.9", true),
        ("1.0", "0.9.9", true),
        ("1.0.1", "1.0", true),
        ("0.2.2", "0.2.2", false),
        ("1.0", "1.0.0", false),
        ("0.2.1", "0.2.2", false),
        ("0.9.9", "1.0.0", false),
    ])
    func comparesVersions(candidate: String, current: String, expected: Bool) {
        #expect(UpdateChecker.isVersion(candidate, newerThan: current) == expected)
    }
}
