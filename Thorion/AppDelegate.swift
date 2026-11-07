import AppKit
import Defaults
import IOKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusBarManager: StatusBarManager!
    private var batteryService: BatteryService!
    private var viewModel: MenuViewModel!
    private var menuBuilder: MenuBuilder!
    private var chargeManager: ChargeManager!
    private var settingsWindowController: SettingsWindowController!
    private var menu: NSMenu!
    private var settingsObservation: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use this app as their host process. Starting it for real would add a
        // menu bar item and drive the charging helper, and on a Mac without a battery (a CI
        // runner is a virtual machine) the check below would end the host before the test
        // runner connects, which fails the whole test run with exit code 65.
        guard !RuntimeEnvironment.isRunningTests else { return }

        // Exit the app immediately if the device doesn't have a battery
        let batteryIOService = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard batteryIOService != 0 else {
            NSApplication.shared.terminate(nil)
            return
        }
        IOObjectRelease(batteryIOService)

        Task {
            await setupServices()
            setupMenu()
            requestNotificationPermissions()
            // Sparkle: daily update checks, download + install on the user's OK.
            UpdateChecker.shared.start()
            LaunchAtLoginSuggestion.suggestIfNeeded()
        }
    }

    private func setupServices() async {
        // Turning charge management on registered the helper, but macOS can lose that
        // registration, and then the LED and adapter commands only time out.
        if Defaults[.manageCharging] {
            ChargingHelperManager.shared.registerIfMissing()
        }
        batteryService = BatteryService()
        await batteryService.loadCapabilities()
        chargeManager = ChargeManager(batteryService: batteryService)
        viewModel = MenuViewModel(
            batteryService: batteryService,
            chargeManager: chargeManager
        )
        settingsWindowController = SettingsWindowController(
            batteryService: batteryService,
            viewModel: viewModel
        )
        menuBuilder = MenuBuilder(
            viewModel: viewModel,
            settingsWindowController: settingsWindowController
        )
        statusBarManager = StatusBarManager(viewModel: viewModel)
    }

    private func setupMenu() {
        menu = menuBuilder.buildMenu()
        menu.delegate = self
        statusBarManager.setMenu(menu)
        observeMenuSettingsChanges()
    }

    private func observeMenuSettingsChanges() {
        settingsObservation = Task { [weak self] in
            for await _ in Defaults.updates(
                [
                    .showPowerSource, .showTimeTillDischarge, .showBatteryCycleCount,
                    .showBatteryHealth, .showBatteryTemperature, .showUptime,
                    .showBatteryMode, .showInternalPower, .showExternalPower,
                    .showPowerDistribution, .showSystemPower, .showAdapterRatedPower,
                    .showCPUTemperature, .showGPUTemperature, .showEnergyApps, .manageCharging,
                ],
                initial: false
            ) {
                self?.rebuildMenu()
            }
        }
    }

    private func rebuildMenu() {
        menuBuilder.populateMenu(menu)
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    // With the menu bar icon hidden, relaunching the app is the only way back into Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindowController?.showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        chargeManager?.stop()
    }

    // Menu items are sized when built, so a helper approval made in System Settings
    // needs a rebuild for the menu's notice to appear or disappear.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let helperManager = ChargingHelperManager.shared
        let previousStatus = helperManager.helperStatus
        helperManager.refreshStatus()
        if helperManager.helperStatus != previousStatus {
            rebuildMenu()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        viewModel.menuWillOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
        viewModel.menuDidClose()
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == UpdateChecker.notificationIdentifier {
            // Opens Sparkle's dialog for the update the notification announced.
            Task { @MainActor in
                UpdateChecker.shared.checkForUpdates()
            }
        }
        completionHandler()
    }
}
