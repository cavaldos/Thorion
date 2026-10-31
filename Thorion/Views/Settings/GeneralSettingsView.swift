import Defaults
import SwiftUI

struct GeneralSettingsView: View {
    @Default(.launchAtLogin) var launchAtLogin
    @Default(.disableNotifications) var disableNotifications
    @Default(.showChargingStatusChangedNotification) var showChargingStatusChangedNotification

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
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
        .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLoginService.shared.setLaunchAtLogin(newValue)
        }
    }
}

private struct UpdateSettingsSection: View {
    @Default(.automaticallyCheckForUpdates) var automaticallyCheckForUpdates
    private let updateChecker = UpdateChecker.shared

    var body: some View {
        Section {
            Toggle("Automatically check for updates", isOn: $automaticallyCheckForUpdates)

            HStack {
                statusView
                Spacer()
                Button("Check Now") {
                    Task {
                        await updateChecker.checkForUpdates(userInitiated: true)
                    }
                }
                .disabled(updateChecker.status == .checking)
            }
        } header: {
            SettingsSectionHeader(
                title: "Updates",
                description: "Thorion \(updateChecker.currentVersion) checks GitHub Releases once a day."
            )
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch updateChecker.status {
        case .idle:
            Text("Not checked yet")
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking…")
                    .foregroundStyle(.secondary)
            }
        case .upToDate:
            Text("Thorion is up to date")
                .foregroundStyle(.secondary)
        case .available(let version, let downloadURL):
            HStack(spacing: 6) {
                Text("Version \(version) is available")
                Link("Download", destination: downloadURL)
            }
        case .failed(let message):
            Text("Update check failed: \(message)")
                .foregroundStyle(.red)
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
