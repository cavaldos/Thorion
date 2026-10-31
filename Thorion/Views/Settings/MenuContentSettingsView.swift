import Defaults
import SwiftUI

struct MenuContentSettingsView: View {
    @Default(.showPowerSource) var showPowerSource
    @Default(.showTimeTillDischarge) var showTimeTillDischarge
    @Default(.showUptime) var showUptime
    @Default(.showBatteryMode) var showBatteryMode
    @Default(.showBatteryTemperature) var showBatteryTemperature
    @Default(.showBatteryCycleCount) var showBatteryCycleCount
    @Default(.showBatteryHealth) var showBatteryHealth
    @Default(.showInternalPower) var showInternalPower
    @Default(.showExternalPower) var showExternalPower
    @Default(.showSystemPower) var showSystemPower
    @Default(.showAdapterRatedPower) var showAdapterRatedPower
    @Default(.showCPUTemperature) var showCPUTemperature
    @Default(.showGPUTemperature) var showGPUTemperature
    @Default(.showPowerDistribution) var showPowerDistribution
    @Default(.showEnergyApps) var showEnergyApps
    @Default(.updatePowerDataInBackground) var updatePowerDataInBackground

    var body: some View {
        Form {
            Section {
                Toggle("Power source", isOn: $showPowerSource)
                Toggle("Time until discharge", isOn: $showTimeTillDischarge)
                Toggle("Uptime", isOn: $showUptime)
                Toggle("Battery mode", isOn: $showBatteryMode)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Status")
                    Text(
                        "General system and battery status information shown in the menu dropdown."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Battery Health") {
                Toggle("Cycle count", isOn: $showBatteryCycleCount)
                Toggle("Health", isOn: $showBatteryHealth)
                Toggle("Temperature", isOn: $showBatteryTemperature)
            }

            Section("Power") {
                Toggle("Battery Power Metrics", isOn: $showInternalPower)
                Toggle("Adapter Power Metrics", isOn: $showExternalPower)
                Toggle("System Power", isOn: $showSystemPower)
                Toggle("Adapter Rated Power", isOn: $showAdapterRatedPower)
            }

            Section("Temperature") {
                Toggle("CPU Temperature", isOn: $showCPUTemperature)
                Toggle("GPU Temperature", isOn: $showGPUTemperature)
            }

            Section {
                Toggle("Power distribution diagram", isOn: $showPowerDistribution)
                Toggle("Update in background", isOn: $updatePowerDataInBackground)
                Toggle("Significant energy apps", isOn: $showEnergyApps)
            } header: {
                Text("Visuals")
            } footer: {
                Text(
                    "When “Update in background” is off, the power distribution diagram only refreshes while the menu or the dashboard is open, which saves energy."
                )
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0)
    }
}

#Preview {
    MenuContentSettingsView()
}
