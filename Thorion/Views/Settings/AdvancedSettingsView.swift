import Defaults
import SwiftUI

struct AdvancedSettingsView: View {
    let viewModel: MenuViewModel

    @Default(.useHardwarePercentage) var useHardwarePercentage

    var body: some View {
        Form {
            Section {
                Toggle("Use hardware percentage", isOn: $useHardwarePercentage)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Battery Reading")
                    Text(
                        "Use the raw battery percentage instead of the macOS calibrated value."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            testSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0)
    }

    private var testSection: some View {
        Section {
            HStack(spacing: 8) {
                Button {
                    viewModel.setTestMode(.charge)
                } label: {
                    Label("Charge (orange LED)", systemImage: "bolt.fill")
                }
                .tint(.orange)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.testMode == .charge)

                Button {
                    viewModel.setTestMode(.hold)
                } label: {
                    Label("Stop charging (green LED)", systemImage: "leaf.fill")
                }
                .tint(.green)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.testMode == .hold)

                Spacer()

                Button("Back to automatic") {
                    viewModel.setTestMode(nil)
                }
                .disabled(viewModel.testMode == nil)
            }
            .disabled(!viewModel.adapterConnected && viewModel.testMode == nil)

            if !ChargingHelperManager.shared.isWorking {
                HStack {
                    Label(
                        "The charging helper is not running, so the LED cannot change color.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.orange)

                    Spacer()

                    Button("Repair") {
                        Task { await ChargingHelperManager.shared.repair() }
                    }
                }
            }

            if !viewModel.adapterConnected {
                Text("Connect the power adapter to use these buttons.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if viewModel.usesNativeChargeLimit {
                Text(
                    "This Mac pauses charging through the macOS charge limit, so charging only stops from 80%."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Charging Test")
                Text(
                    "Overrides the charge limit until you go back to automatic or unplug the adapter."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}
