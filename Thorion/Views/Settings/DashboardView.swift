import Charts
import Defaults
import SwiftUI

struct DashboardView: View {
    let batteryService: BatteryService
    let viewModel: MenuViewModel
    let openChargeControl: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: DashboardLayout.sectionSpacing) {
                PowerFlowCard(viewModel: viewModel)

                HStack(alignment: .top, spacing: DashboardLayout.columnSpacing) {
                    BatterySpecsCard(batteryService: batteryService, viewModel: viewModel)
                    BatteryHealthCard(batteryService: batteryService)
                    PowerAdapterCard(batteryService: batteryService)
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: DashboardLayout.columnSpacing) {
                    BatteryLevelSection(batteryService: batteryService, viewModel: viewModel)
                    BatteryTemperatureSection(batteryService: batteryService)
                    VStack(alignment: .leading, spacing: DashboardLayout.columnSpacing) {
                        ChargeLimitSection(viewModel: viewModel, openChargeControl: openChargeControl)
                        ChipTemperatureSection(viewModel: viewModel)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear { viewModel.beginLiveUpdates() }
        .onDisappear { viewModel.endLiveUpdates() }
    }
}

private enum DashboardLayout {
    static let sectionSpacing: CGFloat = 20
    static let columnSpacing: CGFloat = 16
    static let cardCornerRadius: CGFloat = 16
    static let chartHeight: CGFloat = 150
    static let powerFlowHeight: CGFloat = 200
}

private enum DashboardPalette {
    static let battery = Color.green
    static let adapter = Color.yellow
}

private enum DashboardFormat {
    static let placeholder = "—"

    static func number(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    static func amperes(_ value: Double) -> String {
        number(value, fractionDigits: 2) + " A"
    }

    static func volts(_ value: Double) -> String {
        number(value, fractionDigits: 2) + " V"
    }

    static func watts(_ value: Double) -> String {
        number(value, fractionDigits: 1) + " W"
    }

    static func celsius(_ value: Double?) -> String {
        guard let value, value > 0 else { return placeholder }
        return number(value, fractionDigits: 1) + "°C"
    }

    static func milliampereHours(_ value: Int) -> String {
        guard value > 0 else { return placeholder }
        return value.formatted() + " mAh"
    }

    static func duration(minutes: Int) -> String {
        guard minutes > 0 else { return placeholder }
        return Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated)
        )
    }
}

// MARK: - Building blocks

private struct DashboardCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous)

        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(Color.primary.opacity(0.05)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }
}

private struct CardTitle: View {
    let title: LocalizedStringKey
    let icon: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint)
        }
        .font(.headline)
    }
}

private struct SpecRow: View {
    let label: LocalizedStringKey
    let value: Text
    var detail: Text?

    var body: some View {
        // Values are short readings that must never truncate, so at narrow widths
        // (and with longer translations) the label wraps instead.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            value
                .lineLimit(1)
                .fixedSize()
            if let detail {
                detail
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.callout)
        .monospacedDigit()
    }
}

private struct DashboardStat: View {
    let title: LocalizedStringKey
    let value: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
    }
}

private struct SectionCaption: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Power flow

private struct PowerFlowCard: View {
    let viewModel: MenuViewModel

    private var batteryIcon: String {
        viewModel.chargingMode == .charging ? "battery.100.bolt" : "battery.75"
    }

    var body: some View {
        DashboardCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    PowerReading(title: "Power Adapter", icon: "powerplug", watts: viewModel.adapterPower)
                    Divider().frame(height: 16)
                    PowerReading(title: "System Load", icon: "cpu", watts: viewModel.systemPower)
                    Divider().frame(height: 16)
                    PowerReading(title: "Battery", icon: batteryIcon, watts: abs(viewModel.batteryPower))
                    Spacer(minLength: 0)
                }

                Divider()

                let snapshot = viewModel.powerFlow
                if snapshot.isEmpty {
                    Text("Waiting for power readings…")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: DashboardLayout.powerFlowHeight)
                } else {
                    PowerFlowDiagram(snapshot: snapshot)
                        .frame(height: DashboardLayout.powerFlowHeight)
                }
            }
        }
    }
}

private struct PowerReading: View {
    let title: LocalizedStringKey
    let icon: String
    let watts: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Text(verbatim: DashboardFormat.watts(watts))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .lineLimit(1)
    }
}

// MARK: - Spec cards

private struct BatterySpecsCard: View {
    let batteryService: BatteryService
    let viewModel: MenuViewModel

    private var stateText: Text {
        if viewModel.isSailing {
            return Text("Sailing")
        }
        switch viewModel.chargingMode {
        case .charging: return Text("Charging")
        case .pluggedIn: return Text("Not Charging")
        case .discharging: return Text("Discharging")
        }
    }

    var body: some View {
        let metrics = batteryService.metrics

        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: "Battery", icon: "bolt.fill", tint: DashboardPalette.battery)
                VStack(spacing: 6) {
                    SpecRow(label: "State", value: stateText)
                    SpecRow(
                        label: "Current",
                        value: Text(verbatim: DashboardFormat.amperes(metrics.batteryCurrent))
                    )
                    SpecRow(
                        label: "Voltage",
                        value: Text(verbatim: DashboardFormat.volts(metrics.batteryVoltage))
                    )
                    SpecRow(
                        label: "Wattage",
                        value: Text(verbatim: DashboardFormat.watts(abs(metrics.batteryPower)))
                    )
                    SpecRow(
                        label: "System Load",
                        value: Text(verbatim: DashboardFormat.watts(viewModel.systemPower))
                    )
                    SpecRow(
                        label: "Low Power Mode",
                        value: viewModel.isLowPowerModeEnabled ? Text("On") : Text("Off")
                    )
                    SpecRow(
                        label: "Remaining Charge",
                        value: Text(verbatim: DashboardFormat.milliampereHours(metrics.currentCapacity))
                    )
                }
            }
        }
    }
}

private struct BatteryHealthCard: View {
    let batteryService: BatteryService

    var body: some View {
        let metrics = batteryService.metrics
        let hasCapacities = metrics.designCapacity > 0

        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: "Battery Health", icon: "heart.fill", tint: .pink)
                VStack(spacing: 6) {
                    SpecRow(
                        label: "Design Capacity",
                        value: Text(verbatim: DashboardFormat.milliampereHours(metrics.designCapacity)),
                        detail: hasCapacities ? Text(verbatim: "100%") : nil
                    )
                    SpecRow(
                        label: "Maximum Capacity",
                        value: Text(verbatim: DashboardFormat.milliampereHours(metrics.maxCapacity)),
                        detail: hasCapacities ? Text(verbatim: "\(metrics.batteryHealth)%") : nil
                    )
                    SpecRow(label: "Cycle Count", value: Text(verbatim: "\(metrics.cycleCount)"))
                    SpecRow(
                        label: "Temperature",
                        value: Text(verbatim: DashboardFormat.celsius(metrics.batteryTemperature))
                    )
                }
            }
        }
    }
}

private struct PowerAdapterCard: View {
    let batteryService: BatteryService

    var body: some View {
        let adapter = batteryService.adapterMetrics
        let isConnected = adapter.adapterConnected
        let ratedWatts = batteryService.systemPowerMetrics.adapterRatedWatts

        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: "Power Adapter", icon: "powerplug.fill", tint: DashboardPalette.adapter)
                VStack(spacing: 6) {
                    SpecRow(
                        label: "Status",
                        value: isConnected ? Text("Connected") : Text("Not Connected")
                    )
                    SpecRow(
                        label: "Current",
                        value: Text(
                            verbatim: isConnected
                                ? DashboardFormat.amperes(adapter.adapterCurrent) : DashboardFormat.placeholder
                        )
                    )
                    SpecRow(
                        label: "Voltage",
                        value: Text(
                            verbatim: isConnected
                                ? DashboardFormat.volts(adapter.adapterVoltage) : DashboardFormat.placeholder
                        )
                    )
                    SpecRow(
                        label: "Wattage",
                        value: Text(
                            verbatim: isConnected
                                ? DashboardFormat.watts(adapter.adapterPower) : DashboardFormat.placeholder
                        ),
                        detail: isConnected
                            ? ratedWatts.map {
                                Text(verbatim: "/ " + DashboardFormat.number($0, fractionDigits: 0) + " W")
                            }
                            : nil
                    )
                }
            }
        }
    }
}

// MARK: - History charts

private struct BatteryLevelSection: View {
    let batteryService: BatteryService
    let viewModel: MenuViewModel

    var body: some View {
        let metrics = batteryService.metrics
        let timeTitle: LocalizedStringKey = metrics.isCharging ? "Time to Full" : "Time Remaining"

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                DashboardStat(title: "Battery Level", value: "\(viewModel.displayPercentage)%")
                Spacer(minLength: 8)
                DashboardStat(
                    title: timeTitle,
                    value: DashboardFormat.duration(minutes: metrics.timeRemaining),
                    alignment: .trailing
                )
            }
            DashboardCard(padding: 12) {
                BatteryLevelChart(batteryService: batteryService)
                    .frame(height: DashboardLayout.chartHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct BatteryTemperatureSection: View {
    let batteryService: BatteryService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DashboardStat(
                title: "Battery Temperature",
                value: DashboardFormat.celsius(batteryService.metrics.batteryTemperature)
            )
            DashboardCard(padding: 12) {
                BatteryTemperatureChart(batteryService: batteryService)
                    .frame(height: DashboardLayout.chartHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private enum HistoryChart {
    // Without a floor, the first minutes after launch span so little time that
    // every axis label reads the same minute.
    private static let minimumSpan: TimeInterval = 60 * 60

    static func timeDomain(_ dates: [Date]) -> ClosedRange<Date> {
        let last = dates.last ?? Date()
        let first = min(dates.first ?? last, last.addingTimeInterval(-minimumSpan))
        return first...last
    }
}

/// History is kept in memory, so the charts start empty each time Thorion launches.
private struct ChartPlaceholder: View {
    var message: LocalizedStringKey = "Collecting data…"

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BatteryLevelChart: View {
    let batteryService: BatteryService

    @Default(.useHardwarePercentage) private var useHardwarePercentage
    @Default(.manageCharging) private var manageCharging
    @Default(.chargeLimit) private var chargeLimit

    var body: some View {
        let samples = batteryService.history

        if samples.count < 2 {
            ChartPlaceholder()
        } else {
            Chart {
                ForEach(samples) { sample in
                    let percentage =
                        useHardwarePercentage ? sample.hardwareBatteryPercentage : sample.batteryPercentage

                    AreaMark(
                        x: .value("Time", sample.date),
                        y: .value("Battery Level", percentage)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DashboardPalette.battery.opacity(0.4), DashboardPalette.battery.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Time", sample.date),
                        y: .value("Battery Level", percentage)
                    )
                    .foregroundStyle(DashboardPalette.battery)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }

                if manageCharging {
                    RuleMark(y: .value("Charge limit", chargeLimit))
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .chartXScale(domain: HistoryChart.timeDomain(samples.map(\.date)))
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let percentage = value.as(Int.self) {
                            Text(verbatim: "\(percentage)%")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
    }
}

private struct BatteryTemperatureChart: View {
    let batteryService: BatteryService

    @Default(.manageCharging) private var manageCharging
    @Default(.enableHeatProtectionMode) private var enableHeatProtectionMode
    @Default(.heatProtectionLimit) private var heatProtectionLimit

    private struct Point: Identifiable {
        let date: Date
        let temperature: Double

        var id: Date { date }
    }

    private static let axisPadding = 2.0

    var body: some View {
        let points = batteryService.history.compactMap { sample in
            sample.temperature.map { Point(date: sample.date, temperature: $0) }
        }
        let showsLimit = manageCharging && enableHeatProtectionMode

        if points.isEmpty && batteryService.history.count >= 2 {
            // Some macOS releases stop publishing a battery temperature entirely.
            ChartPlaceholder(message: "Not available on this Mac")
        } else if points.count < 2 {
            ChartPlaceholder()
        } else {
            let temperatures = points.map(\.temperature)
            let lowest = (temperatures.min() ?? 0).rounded(.down) - Self.axisPadding
            let highestReading = temperatures.max() ?? 0
            let highest =
                (showsLimit ? max(highestReading, Double(heatProtectionLimit)) : highestReading).rounded(.up)
                + Self.axisPadding

            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        yStart: .value("Temperature", lowest),
                        yEnd: .value("Temperature", point.temperature)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.4), Color.blue.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Temperature", point.temperature)
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }

                if showsLimit {
                    RuleMark(y: .value("Temperature limit", heatProtectionLimit))
                        .foregroundStyle(Color.red)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .chartXScale(domain: HistoryChart.timeDomain(points.map(\.date)))
            .chartYScale(domain: lowest...highest)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let temperature = value.as(Double.self) {
                            Text(verbatim: DashboardFormat.number(temperature, fractionDigits: 0) + "°")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
    }
}

// MARK: - Side column

private struct ChargeLimitSection: View {
    let viewModel: MenuViewModel
    let openChargeControl: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCaption(title: "Charge Limit")
            DashboardCard(padding: 6) {
                ChargeLimitControlView(viewModel: viewModel, openChargingSettings: openChargeControl)
            }
        }
    }
}

private struct ChipTemperatureSection: View {
    let viewModel: MenuViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCaption(title: "Temperature")
            DashboardCard {
                VStack(spacing: 6) {
                    SpecRow(label: "CPU", value: Text(verbatim: viewModel.cpuTemperatureText))
                    SpecRow(label: "GPU", value: Text(verbatim: viewModel.gpuTemperatureText))
                }
            }
        }
    }
}
