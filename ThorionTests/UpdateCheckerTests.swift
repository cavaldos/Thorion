import Foundation
import Testing

@testable import thorion

@MainActor
struct UpdateCheckerTests {
    /// The test host is the app, so this reads the Info.plist that ships.
    @Test func infoPlistPointsSparkleAtTheThorionFeed() {
        let info = Bundle.main
        #expect(
            info.object(forInfoDictionaryKey: "SUFeedURL") as? String
                == "https://cavaldos.github.io/macos-app-releases/thorion/appcast.xml")
        // Same EdDSA key as Ice and Lumio (SPARKLE_PRIVATE_KEY in CI).
        #expect(
            info.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
                == "5giXQMfuJxsXCpuCn1XxL2IFkBoSiNMiP4rNwAanT7A=")
        #expect(info.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool == true)
    }

    @Test func carriesASwitchedOffLegacySettingOverToSparkle() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: "automaticallyCheckForUpdates")
        defaults.set("0.0.2", forKey: "lastNotifiedUpdateVersion")

        UpdateChecker.migrateLegacySettings(in: defaults)

        #expect(defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool == false)
        #expect(defaults.object(forKey: "automaticallyCheckForUpdates") == nil)
        #expect(defaults.object(forKey: "lastNotifiedUpdateVersion") == nil)
    }

    @Test func leavesSparkleOnWhenTheLegacySettingWasOn() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "automaticallyCheckForUpdates")

        UpdateChecker.migrateLegacySettings(in: defaults)

        #expect(defaults.object(forKey: "SUEnableAutomaticChecks") == nil)
        #expect(defaults.object(forKey: "automaticallyCheckForUpdates") == nil)
    }

    @Test func keepsAChoiceAlreadyMadeInSparkle() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: "automaticallyCheckForUpdates")
        defaults.set(true, forKey: "SUEnableAutomaticChecks")

        UpdateChecker.migrateLegacySettings(in: defaults)

        #expect(defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool == true)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "UpdateCheckerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
