import AppKit
import Defaults
import ServiceManagement

/// Suggests adding Thorion to Login Items when it starts without being one, so the charge
/// limit keeps being applied after a restart.
enum LaunchAtLoginSuggestion {
    /// Whether to ask. A user who already has the item, who removed it in System Settings
    /// (`.requiresApproval`) or who ticked "Don't ask again" is left alone, and `.notFound`
    /// means macOS cannot register this copy of the app at all.
    static func shouldSuggest(status: SMAppService.Status, skipped: Bool) -> Bool {
        !skipped && status == .notRegistered
    }

    /// Keeps the saved toggle in line with macOS, then asks if Thorion is not a login item.
    static func suggestIfNeeded(service: LaunchAtLoginService = .shared) {
        let status = service.status
        Defaults[.launchAtLogin] = status == .enabled

        guard shouldSuggest(status: status, skipped: Defaults[.skipLaunchAtLoginSuggestion]) else {
            return
        }
        present(service: service)
    }

    private static func present(service: LaunchAtLoginService) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Open Thorion at login?")
        alert.informativeText = String(
            localized:
                "Thorion lives in the menu bar and keeps your charge limit applied. Add it to Login Items so it starts whenever you log in. You can change this later in Settings → General."
        )
        alert.addButton(withTitle: String(localized: "Add to Login Items"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don't ask again")

        // Thorion has no Dock icon, so without this the alert opens behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        guard response == .alertFirstButtonReturn else {
            if alert.suppressionButton?.state == .on {
                Defaults[.skipLaunchAtLoginSuggestion] = true
            }
            return
        }

        let status = service.setLaunchAtLogin(true)
        Defaults[.launchAtLogin] = status == .enabled
        switch status {
        case .enabled:
            break
        case .requiresApproval:
            service.openLoginItemsSettings()
        default:
            presentFailure(service: service)
        }
    }

    private static func presentFailure(service: LaunchAtLoginService) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Thorion could not be added to Login Items")
        alert.informativeText = String(
            localized: "You can add it yourself in System Settings → General → Login Items."
        )
        alert.addButton(withTitle: String(localized: "Open Login Items"))
        alert.addButton(withTitle: String(localized: "Ok"))

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            service.openLoginItemsSettings()
        }
    }
}
