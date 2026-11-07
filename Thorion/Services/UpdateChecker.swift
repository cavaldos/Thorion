import AppKit
import Combine
import Defaults
import Foundation
import Observation
import Sparkle
import UserNotifications
import os.log

/// Self-updates through Sparkle, set up like Ice and Lumio. Sparkle reads the feed named by
/// `SUFeedURL` in Info.plist (published to cavaldos/macos-app-releases by
/// script/notify-update.sh after each release), checks it once a day, verifies the download
/// against `SUPublicEDKey`, then installs it and relaunches Thorion.
///
/// A background check that finds an update posts a notification instead of opening a window
/// over the user's work; clicking it (or "Install…" in Settings) shows Sparkle's update dialog.
///
/// Off in Debug builds: an update would replace them with the release build.
@MainActor
@Observable
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()

    nonisolated static let notificationIdentifier = "updateAvailable"

    /// False for Debug builds.
    let isEnabled: Bool

    /// False while a check or an update is already in progress.
    private(set) var canCheckForUpdates = false

    /// The update a background check found and the user has not opened yet.
    private(set) var pendingUpdateVersion: String?

    private(set) var lastUpdateCheckDate: Date?

    /// Mirrors Sparkle's setting (stored by Sparkle in the `SUEnableAutomaticChecks` default).
    var automaticallyChecksForUpdates = false {
        didSet {
            guard let updater = controller?.updater,
                updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates
            else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private let logger = Logger(subsystem: "com.thorion.app", category: "UpdateChecker")

    private override init() {
        #if DEBUG
            isEnabled = false
        #else
            isEnabled = true
        #endif
        super.init()
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Starts Sparkle's scheduled checks. Call once at launch.
    func start() {
        guard isEnabled, controller == nil else { return }
        Self.migrateLegacySettings(in: .standard)

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        self.controller = controller

        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastUpdateCheckDate = $0 }
            .store(in: &cancellables)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &cancellables)
    }

    /// "Check for Updates" and "Install…": Sparkle shows the result, or brings a pending
    /// update to the front.
    func checkForUpdates() {
        guard let controller else { return }
        // Thorion is a menu bar (LSUIElement) app: Sparkle's windows only take input while
        // it is active.
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }

    /// Before Sparkle, Thorion kept its own "check automatically" switch. Carry a switched-off
    /// value over to Sparkle's setting once, then drop the old keys.
    static func migrateLegacySettings(in defaults: UserDefaults) {
        let legacyKey = "automaticallyCheckForUpdates"
        if defaults.object(forKey: legacyKey) as? Bool == false,
            defaults.object(forKey: "SUEnableAutomaticChecks") == nil
        {
            defaults.set(false, forKey: "SUEnableAutomaticChecks")
        }
        defaults.removeObject(forKey: legacyKey)
        defaults.removeObject(forKey: "lastNotifiedUpdateVersion")
    }

    private func postUpdateNotification(version: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            else {
                // Without notifications the update would go unnoticed: show Sparkle's dialog.
                logger.info("Notifications are not allowed, showing the update dialog instead")
                checkForUpdates()
                return
            }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "Thorion \(version) is available")
            content.body = String(
                localized: "You are using version \(currentVersion). Click to install the update.")
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: Self.notificationIdentifier,
                content: content,
                trigger: nil
            )
            do {
                try await center.add(request)
            } catch {
                logger.error("Failed to deliver update notification: \(error)")
            }
        }
    }

    private func removeUpdateNotification() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
    }
}

// Gentle reminders: https://sparkle-project.org/documentation/gentle-reminders
extension UpdateChecker: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Right after launch Sparkle shows its dialog in focus; at any other time Thorion posts a
    /// notification instead, unless the user turned notifications off in Settings.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus || Defaults[.disableNotifications]
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        pendingUpdateVersion = update.displayVersionString

        if handleShowingUpdate {
            // Sparkle's alert can only take input while the app is active.
            NSApp.activate(ignoringOtherApps: true)
        } else if !state.userInitiated {
            postUpdateNotification(version: update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        removeUpdateNotification()
    }

    func standardUserDriverWillFinishUpdateSession() {
        pendingUpdateVersion = nil
        removeUpdateNotification()
    }
}
