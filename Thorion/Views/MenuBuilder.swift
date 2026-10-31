import AppKit
import Defaults
import SwiftUI

@MainActor
class MenuBuilder {
    private let viewModel: MenuViewModel
    private let settingsWindowController: SettingsWindowController

    init(
        viewModel: MenuViewModel,
        settingsWindowController: SettingsWindowController
    ) {
        self.viewModel = viewModel
        self.settingsWindowController = settingsWindowController
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "Thorion")
        populateMenu(menu)
        return menu
    }

    func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(
            createMenuItem(
                view: ChargeLimitControlView(
                    viewModel: viewModel,
                    openChargingSettings: { [weak self, weak menu] in
                        menu?.cancelTracking()
                        self?.settingsWindowController.showSettings(tab: .chargeControl)
                    }
                )
            )
        )

        let sections: [[NSMenuItem]] = [
            buildVisualizationSection(),
            buildInfoSection(),
            buildPowerMetricsSection(),
            buildHardwareSection(),
            buildEnergyAppsSection(),
        ]

        for section in sections where !section.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for item in section {
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: String(localized:  "Settings"),
            action: #selector(handleSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit"),
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func buildInfoSection() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if Defaults[.showPowerSource] {
            items.append(
                createInfoItem(
                    label: String(localized: "Power Source"),
                    keyPath: \.powerSourceText
                )
            )
        }
        if Defaults[.showTimeTillDischarge] {
            items.append(
                createInfoItem(
                    label: String(localized: "Time Remaining"),
                    keyPath: \.timeRemainingText
                )
            )
        }
        if Defaults[.showUptime] {
            items.append(createInfoItem(label: String(localized: "Uptime"), keyPath: \.uptimeText))
        }
        if Defaults[.showBatteryMode] {
            items.append(
                createInfoItem(
                    label: String(localized: "Battery Mode"),
                    keyPath: \.batteryModeText
                )
            )
        }
        if Defaults[.showBatteryTemperature] {
            items.append(
                createInfoItem(
                    label: String(localized: "Battery Temperature"),
                    keyPath: \.batteryTemperatureText
                )
            )
        }

        return items
    }

    private func buildPowerMetricsSection() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if Defaults[.showInternalPower] {
            items.append(
                createInfoItem(
                    label: String(localized: "Battery"),
                    keyPath: \.internalInputText
                )
            )
        }
        if Defaults[.showExternalPower] {
            items.append(
                createInfoItem(
                    label: String(localized: "Adapter"),
                    keyPath: \.externalInputText
                )
            )
        }
        if Defaults[.showSystemPower] {
            items.append(
                createInfoItem(
                    label: String(localized: "System Power"),
                    keyPath: \.systemPowerText
                )
            )
        }
        if Defaults[.showAdapterRatedPower] {
            items.append(
                createInfoItem(
                    label: String(localized: "Adapter Rated Power"),
                    keyPath: \.adapterRatedPowerText
                )
            )
        }
        if Defaults[.showCPUTemperature] {
            items.append(
                createInfoItem(
                    label: String(localized: "CPU Temperature"),
                    keyPath: \.cpuTemperatureText
                )
            )
        }
        if Defaults[.showGPUTemperature] {
            items.append(
                createInfoItem(
                    label: String(localized: "GPU Temperature"),
                    keyPath: \.gpuTemperatureText
                )
            )
        }

        return items
    }

    private func buildVisualizationSection() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if Defaults[.showPowerDistribution] {
            items.append(
                createMenuItem(
                    view: PowerDistributionView(viewModel: viewModel)
                )
            )
        }

        return items
    }

    private func buildEnergyAppsSection() -> [NSMenuItem] {
        guard Defaults[.showEnergyApps] else { return [] }
        return [createMenuItem(view: EnergyAppsMenuView(monitor: viewModel.energyAppsMonitor))]
    }

    private func buildHardwareSection() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if Defaults[.showBatteryCycleCount] {
            items.append(
                createInfoItem(label: String(localized: "Cycle Count"), keyPath: \.cycleCountText)
            )
        }
        if Defaults[.showBatteryHealth] {
            items.append(
                createInfoItem(
                    label: String(localized: "Battery Health"),
                    keyPath: \.batteryHealthText
                )
            )
        }

        return items
    }

    private func createInfoItem(
        label: String,
        keyPath: KeyPath<MenuViewModel, String>
    ) -> NSMenuItem {
        createMenuItem(
            view: BatteryAdditionalInfoObserverView(
                label: label,
                viewModel: viewModel,
                keyPath: keyPath
            )
        )
    }

    private static let menuWidth: CGFloat = 320

    private func createMenuItem<V: View>(view: V) -> NSMenuItem {
        let menuItem = NSMenuItem()
        let sizer = MenuItemSizer(menuItem: menuItem)

        // The content reports its natural height, so items that expand, collapse or
        // change length resize the open menu instead of being clipped or padded.
        let hostingView = NSHostingView(
            rootView: view
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Self.menuWidth, alignment: .top)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                    sizer.resize(to: height)
                }
        )
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: Self.menuWidth,
            height: hostingView.fittingSize.height
        )
        menuItem.view = hostingView

        return menuItem
    }

    @objc private func handleSettings() {
        settingsWindowController.showSettings()
    }

    @objc private func handleQuit() {
        viewModel.quit()
    }
}

@MainActor
private final class MenuItemSizer {
    private weak var menuItem: NSMenuItem?

    init(menuItem: NSMenuItem) {
        self.menuItem = menuItem
    }

    func resize(to height: CGFloat) {
        guard let menuItem, let view = menuItem.view,
            height > 0, abs(view.frame.height - height) > 0.5
        else { return }
        view.setFrameSize(NSSize(width: view.frame.width, height: height))
        menuItem.menu?.itemChanged(menuItem)
    }
}

struct BatteryAdditionalInfoObserverView: View {
    let label: String
    let viewModel: MenuViewModel
    let keyPath: KeyPath<MenuViewModel, String>

    var body: some View {
        BatteryAdditionalInfo(label: label, value: viewModel[keyPath: keyPath])
    }
}
