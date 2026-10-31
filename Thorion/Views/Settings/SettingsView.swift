import SwiftUI
import smc_power

enum SettingsTab: String, CaseIterable, Identifiable {
    case dashboard
    case chargeControl
    case heatProtection
    case sleepBehavior
    case menuBar
    case menuContent
    case general
    case advanced

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .dashboard: "Dashboard"
        case .chargeControl: "Charge Control"
        case .heatProtection: "Heat Protection"
        case .sleepBehavior: "Sleep Behavior"
        case .menuBar: "Menu Bar"
        case .menuContent: "Menu Content"
        case .general: "General"
        case .advanced: "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .chargeControl: "battery.100.bolt"
        case .heatProtection: "thermometer.medium"
        case .sleepBehavior: "moon"
        case .menuBar: "menubar.rectangle"
        case .menuContent: "list.bullet.rectangle"
        case .general: "gearshape"
        case .advanced: "slider.horizontal.3"
        }
    }
}

enum SettingsSidebarSection: CaseIterable, Identifiable {
    case batteryCare
    case appearance
    case other

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .batteryCare: "Battery Care"
        case .appearance: "Appearance"
        case .other: "Other"
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .batteryCare: [.chargeControl, .heatProtection, .sleepBehavior]
        case .appearance: [.menuBar, .menuContent]
        case .other: [.general, .advanced]
        }
    }
}

/// Lets the window controller switch tabs on a Settings window that is already open.
@MainActor
@Observable
final class SettingsNavigation {
    var selectedTab: SettingsTab

    init(selectedTab: SettingsTab) {
        self.selectedTab = selectedTab
    }
}

struct SettingsView: View {
    @Bindable private var navigation: SettingsNavigation

    private let batteryService: BatteryService
    private let viewModel: MenuViewModel

    init(batteryService: BatteryService, viewModel: MenuViewModel, navigation: SettingsNavigation) {
        self.batteryService = batteryService
        self.viewModel = viewModel
        self.navigation = navigation
    }

    private static let sidebarWidth: CGFloat = 220

    // A plain HStack instead of NavigationSplitView: hosted in an AppKit window, the
    // split view ignores its column width and lets the sidebar collapse with no
    // toolbar button to bring it back.
    var body: some View {
        HStack(spacing: 0) {
            List(selection: $navigation.selectedTab) {
                sidebarRow(for: .dashboard)

                ForEach(SettingsSidebarSection.allCases) { section in
                    Section(section.title) {
                        ForEach(section.tabs) { tab in
                            sidebarRow(for: tab)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
            .frame(width: Self.sidebarWidth)

            Divider()
                .ignoresSafeArea()

            detail(for: navigation.selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 640)
    }

    private func sidebarRow(for tab: SettingsTab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(systemName: tab.icon)
        }
        .tag(tab)
    }

    private var sidebarFooter: some View {
        HStack {
            Button {
                viewModel.quit()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Quit Thorion")
            .accessibilityLabel(Text("Quit Thorion"))

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func detail(for tab: SettingsTab) -> some View {
        let capabilities = batteryService.deviceCapabilities
        let openChargeControl: @MainActor @Sendable () -> Void = { [navigation] in
            navigation.selectedTab = .chargeControl
        }

        switch tab {
        case .dashboard:
            DashboardView(
                batteryService: batteryService,
                viewModel: viewModel,
                openChargeControl: openChargeControl
            )
        case .chargeControl:
            SettingsPage(tab: tab) {
                ChargeControlSettingsView(
                    capabilities: capabilities,
                    usesNativeChargeLimit: batteryService.chargeInhibitMethod == .nativeChargeLimit
                )
            }
        case .heatProtection:
            SettingsPage(tab: tab) {
                HeatProtectionSettingsView(
                    capabilities: capabilities,
                    openChargeControl: openChargeControl
                )
            }
        case .sleepBehavior:
            SettingsPage(tab: tab) {
                SleepBehaviorSettingsView(openChargeControl: openChargeControl)
            }
        case .menuBar:
            SettingsPage(tab: tab) {
                MenuBarSettingsView()
            }
        case .menuContent:
            SettingsPage(tab: tab) {
                MenuContentSettingsView()
            }
        case .general:
            SettingsPage(tab: tab) {
                GeneralSettingsView()
            }
        case .advanced:
            SettingsPage(tab: tab) {
                AdvancedSettingsView()
            }
        }
    }
}

/// The window hides its title bar, so each page shows its own title.
private struct SettingsPage<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text(tab.title)
            } icon: {
                Image(systemName: tab.icon)
                    .foregroundStyle(Color.accentColor)
            }
            .font(.title2.weight(.semibold))
            .padding(.horizontal, 24)
            .padding(.bottom, 4)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    let batteryService = BatteryService()
    SettingsView(
        batteryService: batteryService,
        viewModel: MenuViewModel(
            batteryService: batteryService,
            chargeManager: ChargeManager(batteryService: batteryService)
        ),
        navigation: SettingsNavigation(selectedTab: .dashboard)
    )
}
