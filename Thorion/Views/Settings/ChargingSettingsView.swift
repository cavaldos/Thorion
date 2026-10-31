import Defaults
import SwiftUI
import os.log
import smc_power

struct ChargeControlSettingsView: View {
    @Default(.manageCharging) var manageCharging
    @Default(.chargeLimit) var chargeLimit
    @Default(.sailingMode) var sailingMode
    @Default(.sailingModeLimit) var sailingModeLimit
    @Default(.automaticDischarge) var automaticDischarge
    @Default(.manageMagSafeLED) var manageMagSafeLED
    @State private var helperManager = ChargingHelperManager.shared
    @State private var installError: String?

    private let capabilities: DeviceCapabilities
    private let usesNativeChargeLimit: Bool

    private let logger = Logger(
        subsystem: "com.thorion.app",
        category: "ChargeControlSettingsView"
    )

    init(capabilities: DeviceCapabilities, usesNativeChargeLimit: Bool = false) {
        self.capabilities = capabilities
        self.usesNativeChargeLimit = usesNativeChargeLimit
    }

    private var hasChargingControl: Bool {
        capabilities.chargingControl
    }

    private var hasAdapterControl: Bool {
        capabilities.adapterControl
    }

    private var hasAnyControl: Bool {
        hasChargingControl || hasAdapterControl
    }

    private var sailingResumePercentage: Int {
        chargeLimit - sailingModeLimit
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Manage charging",
                    isOn: Binding(
                        get: { manageCharging },
                        set: { newValue in
                            toggleManageCharging(newValue)
                        }
                    )
                )
                .disabled(!hasAnyControl || helperManager.helperStatus == .requiresApproval)

                if helperManager.helperStatus == .requiresApproval {
                    LabeledContent {
                        HStack {
                            Button("Open Login Items") {
                                helperManager.openLoginItemsSettings()
                            }
                            Button("Check Again") {
                                checkApprovalStatus()
                            }
                        }
                    } label: {
                        // Without a Team ID signature, macOS lists the daemon by its executable name.
                        Text(
                            "Allow \u{201C}charging-helper\u{201D} in System Settings \u{2192} Login Items & Extensions to continue."
                        )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if manageCharging {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { Double(chargeLimit) },
                                    set: { chargeLimit = Int($0) }
                                ),
                                in: Double(ChargeLimitScale.range.lowerBound)...Double(
                                    ChargeLimitScale.range.upperBound),
                                step: Double(ChargeLimitScale.step)
                            )
                            Text("\(chargeLimit)%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    } label: {
                        Text("Charge limit")
                    }
                }
            } header: {
                SettingsSectionHeader(
                    title: "Charge Management",
                    description: "Limit the maximum charge level to extend battery lifespan."
                )
            } footer: {
                if !hasAnyControl {
                    Text("Charge management is not supported on this device.")
                } else if manageCharging && usesNativeChargeLimit
                    && chargeLimit < NativeChargeLimitService.supportedRange.lowerBound
                {
                    Text(
                        "On this version of macOS, charging is paused through the macOS charge limit, which cannot hold the battery below 80%."
                    )
                }
            }

            if manageCharging {
                Section {
                    Toggle("Automatic discharge", isOn: $automaticDischarge)
                        .disabled(!hasAdapterControl)
                } header: {
                    SettingsSectionHeader(
                        title: "Discharge",
                        description:
                            "Discharge the battery to your charge limit when plugged in above the target level."
                    )
                } footer: {
                    if !hasAdapterControl {
                        Text("Adapter control is not supported on this device.")
                    }
                }

                Section {
                    Toggle("Enable sailing mode", isOn: $sailingMode)
                        .disabled(!hasChargingControl)

                    if sailingMode {
                        LabeledContent {
                            HStack(spacing: 8) {
                                Slider(
                                    value: Binding(
                                        get: { Double(sailingModeLimit) },
                                        set: { sailingModeLimit = Int($0) }
                                    ), in: 1...20, step: 1
                                )
                                Text("\(sailingModeLimit)%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        } label: {
                            Text("Threshold below limit")
                        }

                        LabeledContent("Charging resumes at") {
                            Text("\(sailingResumePercentage)%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    SettingsSectionHeader(
                        title: "Sailing Mode",
                        description:
                            "Automatically resume charging when the battery drops below the threshold relative to your charge limit."
                    )
                } footer: {
                    if !hasChargingControl {
                        Text("Charging control is not supported on this device.")
                    }
                }

                if capabilities.hasMagSafe {
                    Section {
                        Toggle("Manage MagSafe LED", isOn: $manageMagSafeLED)
                            .disabled(!capabilities.magsafeLEDControl)
                    } header: {
                        Text("MagSafe LED Control")
                    } footer: {
                        if !capabilities.magsafeLEDControl {
                            Text("MagSafe LED control is not supported on this device.")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0)
        .animation(.default, value: manageCharging)
        .animation(.default, value: sailingMode)
        .animation(.default, value: helperManager.helperStatus)
        .alert(
            "Failed to install charging helper",
            isPresented: Binding(
                get: { installError != nil },
                set: { if !$0 { installError = nil } }
            )
        ) {
            Button("Ok") { installError = nil }
        } message: {
            if let installError {
                Text(installError)
            }
        }
    }

    private func toggleManageCharging(_ enabled: Bool) {
        do {
            if enabled {
                try helperManager.install()
                if helperManager.helperStatus == .installed {
                    manageCharging = true
                }
            } else {
                try helperManager.uninstall()
                manageCharging = false
            }
        } catch {
            logger.error("Failed to \(enabled ? "install" : "uninstall") charging helper: \(error)")
            installError = error.localizedDescription
        }
    }

    private func checkApprovalStatus() {
        helperManager.refreshStatus()
        if helperManager.helperStatus == .installed {
            manageCharging = true
        }
    }
}

struct HeatProtectionSettingsView: View {
    @Default(.manageCharging) var manageCharging
    @Default(.enableHeatProtectionMode) var enableHeatProtectionMode
    @Default(.heatProtectionLimit) var heatProtectionLimit
    @Default(.manageMagSafeLED) var manageMagSafeLED
    @Default(.heatProtectionMagSafeLEDState) var heatProtectionMagSafeLEDState

    let capabilities: DeviceCapabilities
    let openChargeControl: @MainActor () -> Void

    var body: some View {
        Form {
            if !manageCharging {
                ChargeManagementOffSection(openChargeControl: openChargeControl)
            }

            Section {
                Toggle("Enable heat protection", isOn: $enableHeatProtectionMode)
                    .disabled(!capabilities.chargingControl)

                if enableHeatProtectionMode {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { Double(heatProtectionLimit) },
                                    set: { heatProtectionLimit = Int($0) }
                                ), in: 30...50, step: 1
                            )
                            Text("\(heatProtectionLimit)°C")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    } label: {
                        Text("Temperature limit")
                    }

                    if capabilities.hasMagSafe && manageMagSafeLED {
                        Picker(
                            "LED during heat protection",
                            selection: $heatProtectionMagSafeLEDState
                        ) {
                            Text("Off").tag(MagSafeLEDState.off)
                            Text("Green").tag(MagSafeLEDState.green)
                            Text("Orange").tag(MagSafeLEDState.orange)
                            Text("Blinking Orange Slow").tag(MagSafeLEDState.blinkOrangeSlow)
                            Text("Blinking Orange Fast").tag(MagSafeLEDState.blinkOrangeFast)
                        }
                        .disabled(!capabilities.magsafeLEDControl)
                    }
                }
            } header: {
                SettingsSectionHeader(
                    title: "Heat Protection",
                    description: "Pause charging when the battery temperature exceeds the threshold."
                )
            } footer: {
                if !capabilities.chargingControl {
                    Text("Charging control is not supported on this device.")
                }
            }
            .disabled(!manageCharging)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0)
        .animation(.default, value: enableHeatProtectionMode)
        .animation(.default, value: manageCharging)
    }
}

struct SleepBehaviorSettingsView: View {
    @Default(.manageCharging) var manageCharging
    @Default(.disableSleepUntilChargeLimit) var disableSleepUntilChargeLimit

    let openChargeControl: @MainActor () -> Void

    var body: some View {
        Form {
            if !manageCharging {
                ChargeManagementOffSection(openChargeControl: openChargeControl)
            }

            Section {
                Toggle("Disable sleep until charge limit", isOn: $disableSleepUntilChargeLimit)
            } header: {
                SettingsSectionHeader(
                    title: "Sleep Prevention",
                    description:
                        "Prevent your Mac from sleeping while charging towards the charge limit. Sleep is re-enabled once the limit is reached or the adapter is disconnected."
                )
            }
            .disabled(!manageCharging)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0)
        .animation(.default, value: manageCharging)
    }
}

/// These pages only take effect while charge management is on, which is switched on
/// from Charge Control because turning it on may install the charging helper.
private struct ChargeManagementOffSection: View {
    let openChargeControl: @MainActor () -> Void

    var body: some View {
        Section {
            LabeledContent {
                Button("Open Charge Control", action: openChargeControl)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Charge management is off")
                        Text("Turn on charge management to use these settings.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

struct SettingsSectionHeader: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ChargeControlSettingsView(
        capabilities: DeviceCapabilities(
            chargingControl: true,
            adapterControl: true,
            hasMagSafe: true,
            magsafeLEDControl: true
        )
    )
}

#Preview {
    HeatProtectionSettingsView(
        capabilities: DeviceCapabilities(
            chargingControl: true,
            adapterControl: true,
            hasMagSafe: true,
            magsafeLEDControl: true
        ),
        openChargeControl: {}
    )
}
