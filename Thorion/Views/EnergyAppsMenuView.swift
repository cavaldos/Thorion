import Defaults
import SwiftUI

/// Collapsible "Significant Energy Apps" section, styled after the system Battery menu.
struct EnergyAppsMenuView: View {
    let monitor: EnergyAppsMonitor
    @Default(.energyAppsExpanded) private var isExpanded
    @State private var isHeaderHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header

            if isExpanded {
                if monitor.apps.isEmpty {
                    Text("No Apps Using Significant Energy")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                } else {
                    ForEach(monitor.apps) { app in
                        EnergyAppRow(app: app)
                    }
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack {
                Text("Significant Energy Apps")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHeaderHovered ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHeaderHovered = $0 }
    }
}

private struct EnergyAppRow: View {
    let app: EnergyApp

    var body: some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app")
                    .frame(width: 20, height: 20)
            }
            Text(app.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Text(app.impact.formatted(.number.precision(.fractionLength(1))))
                .monospacedDigit()
                .foregroundStyle(app.impact >= EnergyAppsMonitor.highImpact ? Color.orange : Color.blue)
        }
        .font(.callout)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
    }
}
