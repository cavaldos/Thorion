import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var navigation: SettingsNavigation?
    private let batteryService: BatteryService
    private let viewModel: MenuViewModel

    init(batteryService: BatteryService, viewModel: MenuViewModel) {
        self.batteryService = batteryService
        self.viewModel = viewModel
        super.init()
    }

    func showSettings(tab: SettingsTab? = nil) {
        if let window, let navigation {
            if let tab {
                navigation.selectedTab = tab
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let navigation = SettingsNavigation(selectedTab: tab ?? .dashboard)
        let settingsView = SettingsView(
            batteryService: batteryService,
            viewModel: viewModel,
            navigation: navigation
        )
        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = String(localized: "Thorion Settings")
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.center()
        newWindow.setFrameAutosaveName("SettingsWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
        self.navigation = navigation
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            window = nil
            navigation = nil
        }
    }
}
