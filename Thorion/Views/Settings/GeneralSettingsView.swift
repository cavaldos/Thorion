import Defaults
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Default(.launchAtLogin) var launchAtLogin
    @Default(.disableNotifications) var disableNotifications
    @Default(.showChargingStatusChangedNotification) var showChargingStatusChangedNotification

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { setLaunchAtLogin($0) }
                    )
                )
            }

            Section {
                Toggle("Disable all notifications", isOn: $disableNotifications)
                Toggle("Charging status changed", isOn: $showChargingStatusChangedNotification)
                    .disabled(disableNotifications)
            } header: {
                SettingsSectionHeader(
                    title: "Notifications",
                    description: "Control when Thorion sends you notifications."
                )
            }

            UpdateSettingsSection()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0)
        // The item can be added or removed in System Settings, so show what macOS says.
        .onAppear { launchAtLogin = LaunchAtLoginService.shared.isEnabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let status = LaunchAtLoginService.shared.setLaunchAtLogin(enabled)
        // Show what macOS did rather than what was asked for: it may wait for the user's approval.
        launchAtLogin = status == .enabled
        if enabled, status == .requiresApproval {
            LaunchAtLoginService.shared.openLoginItemsSettings()
        }
    }
}

private struct UpdateSettingsSection: View {
    @Bindable private var updateChecker = UpdateChecker.shared

    var body: some View {
        Section {
            if updateChecker.isEnabled {
                Toggle("Automatically check for updates", isOn: $updateChecker.automaticallyChecksForUpdates)

                HStack {
                    statusView
                    Spacer()
                    if updateChecker.pendingUpdateVersion != nil {
                        Button("Install…") {
                            updateChecker.checkForUpdates()
                        }
                    } else {
                        Button("Check Now") {
                            updateChecker.checkForUpdates()
                        }
                        .disabled(!updateChecker.canCheckForUpdates)
                    }
                }
            } else {
                Text("Updates are off in Debug builds.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            SettingsSectionHeader(
                title: "Updates",
                description:
                    "Thorion \(updateChecker.currentVersion) checks for a new version once a day and installs it when you agree."
            )
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if let version = updateChecker.pendingUpdateVersion {
            Text("Version \(version) is available")
        } else if let lastCheck = updateChecker.lastUpdateCheckDate {
            Text("Last checked \(lastCheck, format: .relative(presentation: .named))")
                .foregroundStyle(.secondary)
        } else {
            Text("Not checked yet")
                .foregroundStyle(.secondary)
        }
    }
}

struct MenuBarSettingsView: View {
    @Default(.statusIconStyle) var statusIconStyle
    @Default(.showPercentageNextToIcon) var showPercentageNextToIcon

    var body: some View {
        Form {
            Section {
                StatusIconStylePicker(selection: $statusIconStyle)
                Toggle("Show percentage next to icon", isOn: $showPercentageNextToIcon)
                    .disabled(!statusIconStyle.supportsPercentageNextToIcon)
            } header: {
                SettingsSectionHeader(
                    title: "Menu Bar Icon",
                    description: "Choose how Thorion appears in the menu bar."
                )
            } footer: {
                if statusIconStyle == .hidden {
                    Text("Open Thorion again from the Applications folder to show Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0)
    }
}

private struct StatusIconStylePicker: View {
    @Binding var selection: StatusIconStyle

    private enum Layout {
        static let tileMinimumWidth: CGFloat = 130
        static let spacing: CGFloat = 10
        static let cornerRadius: CGFloat = 10
        static let previewHeight: CGFloat = 22
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Layout.tileMinimumWidth), spacing: Layout.spacing)],
            spacing: Layout.spacing
        ) {
            ForEach(StatusIconStyle.allCases) { style in
                tile(for: style)
            }
        }
        .padding(.vertical, 4)
    }

    private func tile(for style: StatusIconStyle) -> some View {
        let isSelected = selection == style
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)

        return Button {
            selection = style
        } label: {
            VStack(spacing: 8) {
                preview(for: style)
                    .frame(height: Layout.previewHeight)
                Text(title(for: style))
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(shape.fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
            .overlay(
                shape.strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                    lineWidth: isSelected ? 2 : 1
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func preview(for style: StatusIconStyle) -> some View {
        if style == .hidden {
            Image(systemName: "eye.slash")
        } else {
            BatteryIndicatorView(batteryLevel: 75, chargingMode: .pluggedIn, style: style)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }

    private func title(for style: StatusIconStyle) -> LocalizedStringKey {
        switch style {
        case .hidden: "Don't Show"
        case .logo: "Thorion Logo"
        case .status: "Thorion Status"
        case .macOS27: "macOS 27"
        case .macOS26: "macOS 26"
        case .macOS26Colored: "macOS 26 Colored"
        case .iOSNative: "iOS Native"
        }
    }
}

#Preview {
    GeneralSettingsView()
}

#Preview {
    MenuBarSettingsView()
}
