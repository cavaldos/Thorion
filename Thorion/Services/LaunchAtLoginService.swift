import Foundation
import ServiceManagement
import os.log

class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    private let logger = Logger(
        subsystem: "com.thorion.app",
        category: "LaunchAtLoginService"
    )

    private init() {}

    /// What macOS says about Thorion being a login item. This is the truth, not the saved
    /// toggle: the item can be removed in System Settings → Login Items at any time.
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    var isEnabled: Bool {
        status == .enabled
    }

    /// Adds or removes Thorion as a login item and returns the status afterwards, so the
    /// caller can tell when macOS did not (or not yet) turn it on. `.requiresApproval`
    /// means the user still has to allow it in System Settings.
    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> SMAppService.Status {
        let service = SMAppService.mainApp
        do {
            if enabled {
                // register() throws for an item that is already on.
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            logger.error(
                "Failed to \(enabled ? "enable" : "disable") launch at login: \(error, privacy: .public)"
            )
        }
        return service.status
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
