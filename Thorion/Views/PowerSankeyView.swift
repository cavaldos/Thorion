import SwiftUI

/// The readings the power distribution diagram is drawn from.
///
/// The system load is derived from the adapter and battery readings instead of taken
/// from the SMC total: that key lags the adapter reading by a second, so the two sides
/// of the diagram never added up. Deriving it keeps "adapter = battery + MacBook".
struct PowerFlowSnapshot: Equatable {
    /// Readings below this are sensor noise, not a flow worth drawing.
    static let minimumVisibleWatts = 0.05
    /// The battery hovers around zero while charging is paused; below this it is idle.
    static let minimumBatteryWatts = 0.3

    var adapterWatts: Double = 0
    /// Positive while the battery charges, negative while it powers the Mac.
    var batteryWatts: Double = 0
    var cpuWatts: Double?
    var displayWatts: Double?
    /// The SMC system total, used only when neither the adapter nor the battery reports.
    var measuredSystemWatts: Double?

    var chargeWatts: Double {
        batteryWatts >= Self.minimumBatteryWatts ? batteryWatts : 0
    }

    var dischargeWatts: Double {
        batteryWatts <= -Self.minimumBatteryWatts ? -batteryWatts : 0
    }

    var systemWatts: Double {
        if adapterWatts > Self.minimumVisibleWatts || dischargeWatts > 0 {
            return max(adapterWatts + dischargeWatts - chargeWatts, 0)
        }
        return measuredSystemWatts ?? 0
    }

    var isEmpty: Bool {
        adapterWatts <= Self.minimumVisibleWatts && dischargeWatts == 0
            && systemWatts <= Self.minimumVisibleWatts
    }

    /// Moves `weight` (0...1) of the way toward `target`.
    func blended(toward target: PowerFlowSnapshot, weight: Double) -> PowerFlowSnapshot {
        let weight = min(max(weight, 0), 1)
        func mix(_ current: Double, _ next: Double) -> Double {
            current + (next - current) * weight
        }
        func mix(_ current: Double?, _ next: Double?) -> Double? {
            guard let current, let next else { return next }
            return mix(current, next)
        }
        return PowerFlowSnapshot(
            adapterWatts: mix(adapterWatts, target.adapterWatts),
            batteryWatts: mix(batteryWatts, target.batteryWatts),
            cpuWatts: mix(cpuWatts, target.cpuWatts),
            displayWatts: mix(displayWatts, target.displayWatts),
            measuredSystemWatts: mix(measuredSystemWatts, target.measuredSystemWatts)
        )
    }
}

enum PowerFlowFormat {
    /// Three significant digits, so small loads such as the display keep their precision
    /// without large ones gaining meaningless decimals.
    static func watts(_ value: Double) -> String {
        let magnitude = abs(value)
        let fractionDigits = magnitude < 10 ? 2 : (magnitude < 100 ? 1 : 0)
        return magnitude.formatted(.number.precision(.fractionLength(fractionDigits))) + " W"
    }

    /// Whole watts, for the narrow total inside a node.
    static func compactWatts(_ value: Double) -> String {
        abs(value).formatted(.number.precision(.fractionLength(0))) + " W"
    }
}

struct PowerFlowStyle {
    var nodeWidth: CGFloat
    var sinkNodeWidth: CGFloat
    var nodeCornerRadius: CGFloat
    var nodeGap: CGFloat
    var bandInset: CGFloat
    var minimumBandHeight: CGFloat
    var iconSize: CGFloat
    var labelSize: CGFloat
    /// Where the middle column (battery and MacBook) sits across the width.
    var hubPosition: CGFloat

    static let menu = PowerFlowStyle(
        nodeWidth: 30,
        sinkNodeWidth: 34,
        nodeCornerRadius: 8,
        nodeGap: 5,
        bandInset: 4,
        minimumBandHeight: 19,
        iconSize: 13,
        labelSize: 11,
        hubPosition: 0.4
    )

    static let dashboard = PowerFlowStyle(
        nodeWidth: 52,
        sinkNodeWidth: 60,
        nodeCornerRadius: 12,
        nodeGap: 8,
        bandInset: 6,
        minimumBandHeight: 28,
        iconSize: 17,
        labelSize: 13,
        hubPosition: 0.4
    )
}

/// Three columns, as in the system's own power view:
///
///     Adapter ──┬── Battery (charging)
///               └── MacBook ──┬── CPU
///     Battery ──────┘         ├── Display
///     (discharging)           └── Other
///
/// Node heights follow their watts within each column, and every band starts and ends
/// inside the nodes it joins, so a split such as adapter → battery + MacBook reads at a glance.
struct PowerFlowDiagram: View {
    let snapshot: PowerFlowSnapshot
    var style: PowerFlowStyle = .dashboard

    var body: some View {
        GeometryReader { geometry in
            let layout = PowerFlowLayout(
                size: geometry.size,
                graph: PowerFlowGraph(snapshot: snapshot),
                style: style
            )

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for band in layout.bands {
                        context.fill(
                            band.path,
                            with: .linearGradient(
                                Gradient(colors: [band.startColor, band.endColor]),
                                startPoint: CGPoint(x: band.bounds.minX, y: band.bounds.midY),
                                endPoint: CGPoint(x: band.bounds.maxX, y: band.bounds.midY)
                            )
                        )
                    }
                }

                ForEach(layout.nodes) { node in
                    PowerFlowNodeView(node: node, style: style)
                        .frame(width: node.frame.width, height: node.frame.height)
                        .position(x: node.frame.midX, y: node.frame.midY)
                }

                ForEach(layout.bands) { band in
                    Text(verbatim: PowerFlowFormat.watts(band.watts))
                        .font(.system(size: style.labelSize, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        .position(band.labelPosition)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Power distribution"))
        .accessibilityValue(Text(verbatim: accessibilityValue))
    }

    private var accessibilityValue: String {
        let graph = PowerFlowGraph(snapshot: snapshot)
        return graph.links
            .map { "\($0.from) → \($0.to): \(PowerFlowFormat.watts($0.watts))" }
            .joined(separator: ", ")
    }
}

/// The compact diagram shown in the status menu.
struct PowerDistributionView: View {
    let viewModel: MenuViewModel

    private static let height: CGFloat = 118

    var body: some View {
        let snapshot = viewModel.powerFlow

        Group {
            if snapshot.isEmpty {
                Text("Waiting for power readings…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PowerFlowDiagram(snapshot: snapshot, style: .menu)
            }
        }
        .frame(height: Self.height)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct PowerFlowNodeView: View {
    let node: PowerFlowLayout.PlacedNode
    let style: PowerFlowStyle

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.nodeCornerRadius, style: .continuous)

        shape
            .fill(Color.primary.opacity(0.07))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
            .overlay {
                VStack(spacing: 2) {
                    Image(systemName: node.icon)
                        .font(.system(size: style.iconSize, weight: .medium))
                        .foregroundStyle(node.tint ?? Color.secondary)
                    if let valueText = node.valueText {
                        Text(verbatim: valueText)
                            .font(.system(size: style.labelSize - 2, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 2)
                    }
                }
            }
            .help(Text(node.title))
    }
}

/// Which nodes exist and how many watts flow between them, before any geometry.
private struct PowerFlowGraph {
    struct Node {
        let id: String
        let title: LocalizedStringKey
        let icon: String
        let color: Color
        /// Whether the icon takes `color`; power sources keep a neutral icon.
        let tintsIcon: Bool
        let column: Int
        let watts: Double
    }

    struct Link {
        let from: String
        let to: String
        let watts: Double
    }

    static let macBookColor = Color(red: 0.42, green: 0.53, blue: 0.75)
    static let columnCount = 3

    private(set) var nodes: [Node] = []
    private(set) var links: [Link] = []

    init(snapshot: PowerFlowSnapshot) {
        let minimum = PowerFlowSnapshot.minimumVisibleWatts
        let charge = snapshot.chargeWatts
        let discharge = snapshot.dischargeWatts
        let system = snapshot.systemWatts
        let adapter = snapshot.adapterWatts

        // Column 0: where the power comes from.
        if adapter > minimum {
            nodes.append(
                Node(
                    id: "adapter", title: "Power Adapter", icon: "powerplug.fill", color: .gray,
                    tintsIcon: false, column: 0, watts: adapter
                )
            )
        }
        if discharge > 0 {
            nodes.append(
                Node(
                    id: "battery-source", title: "Battery", icon: "battery.75", color: .green,
                    tintsIcon: true, column: 0, watts: discharge
                )
            )
        }

        // Column 1: the battery while it charges, and the MacBook.
        if charge > 0 && adapter > minimum {
            nodes.append(
                Node(
                    id: "battery-sink", title: "Battery", icon: "battery.100.bolt", color: .green,
                    tintsIcon: true, column: 1, watts: min(charge, adapter)
                )
            )
            links.append(Link(from: "adapter", to: "battery-sink", watts: min(charge, adapter)))
        }
        nodes.append(
            Node(
                id: "macbook", title: "MacBook", icon: "laptopcomputer", color: Self.macBookColor,
                tintsIcon: false, column: 1, watts: system
            )
        )
        let adapterToMac = adapter - min(charge, adapter)
        if adapter > minimum && adapterToMac > minimum {
            links.append(Link(from: "adapter", to: "macbook", watts: adapterToMac))
        }
        if discharge > 0 {
            links.append(Link(from: "battery-source", to: "macbook", watts: discharge))
        }

        // Column 2: what the MacBook spends it on.
        var unattributed = system
        var hasBreakdown = false
        if let cpu = snapshot.cpuWatts, cpu > minimum {
            let watts = min(cpu, unattributed)
            addLoad(id: "cpu", title: "CPU", icon: "cpu", color: .purple, watts: watts)
            unattributed -= watts
            hasBreakdown = true
        }
        if let display = snapshot.displayWatts, display > minimum {
            let watts = min(display, max(unattributed, 0))
            addLoad(id: "display", title: "Display", icon: "display", color: .orange, watts: watts)
            unattributed -= watts
            hasBreakdown = true
        }
        if unattributed > minimum {
            addLoad(
                id: "other", title: hasBreakdown ? "Other" : "System Load", icon: "ellipsis",
                color: .mint, watts: unattributed
            )
        }
    }

    private mutating func addLoad(
        id: String, title: LocalizedStringKey, icon: String, color: Color, watts: Double
    ) {
        guard watts > PowerFlowSnapshot.minimumVisibleWatts else { return }
        nodes.append(
            Node(id: id, title: title, icon: icon, color: color, tintsIcon: true, column: 2, watts: watts)
        )
        links.append(Link(from: "macbook", to: id, watts: watts))
    }
}

private struct PowerFlowLayout {
    struct PlacedNode: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let icon: String
        let tint: Color?
        let frame: CGRect
        let valueText: String?
    }

    struct Band: Identifiable {
        let id: String
        let path: Path
        let bounds: CGRect
        let watts: Double
        let labelPosition: CGPoint
        let startColor: Color
        let endColor: Color
    }

    private static let bandOpacity = 0.55

    private(set) var nodes: [PlacedNode] = []
    private(set) var bands: [Band] = []

    init(size: CGSize, graph: PowerFlowGraph, style: PowerFlowStyle) {
        let hubX = min(
            max(size.width * style.hubPosition - style.nodeWidth / 2, style.nodeWidth * 2),
            size.width - style.sinkNodeWidth - style.nodeWidth * 2
        )
        let columnX: [CGFloat] = [0, hubX, size.width - style.sinkNodeWidth]
        let columnWidth: [CGFloat] = [style.nodeWidth, style.nodeWidth, style.sinkNodeWidth]

        // Stack each column's nodes, sized by their watts.
        var frames: [String: CGRect] = [:]
        for column in 0..<PowerFlowGraph.columnCount {
            let columnNodes = graph.nodes.filter { $0.column == column }
            guard !columnNodes.isEmpty else { continue }
            let totalGap = style.nodeGap * CGFloat(columnNodes.count - 1)
            let heights = Self.distribute(
                columnNodes.map(\.watts), across: size.height - totalGap, minimum: style.minimumBandHeight
            )
            var y: CGFloat = 0
            for (index, node) in columnNodes.enumerated() {
                frames[node.id] = CGRect(
                    x: columnX[column], y: y, width: columnWidth[column], height: heights[index]
                )
                y += heights[index] + style.nodeGap
            }
        }

        // Split each node's edge between its links, in the order the other ends are stacked
        // so bands never cross.
        var outgoingSpans: [Int: ClosedRange<CGFloat>] = [:]
        var incomingSpans: [Int: ClosedRange<CGFloat>] = [:]
        let indexedLinks = Array(graph.links.enumerated())

        for node in graph.nodes {
            guard let frame = frames[node.id] else { continue }

            let outgoing = indexedLinks
                .filter { $0.element.from == node.id }
                .sorted { (frames[$0.element.to]?.minY ?? 0) < (frames[$1.element.to]?.minY ?? 0) }
            for (offset, range) in Self.spans(of: outgoing.map(\.element.watts), in: frame, style: style).enumerated() {
                outgoingSpans[outgoing[offset].offset] = range
            }

            let incoming = indexedLinks
                .filter { $0.element.to == node.id }
                .sorted { (frames[$0.element.from]?.minY ?? 0) < (frames[$1.element.from]?.minY ?? 0) }
            for (offset, range) in Self.spans(of: incoming.map(\.element.watts), in: frame, style: style).enumerated() {
                incomingSpans[incoming[offset].offset] = range
            }
        }

        let colors = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.color) })

        for (index, link) in indexedLinks {
            guard let fromFrame = frames[link.from], let toFrame = frames[link.to],
                let startSpan = outgoingSpans[index], let endSpan = incomingSpans[index]
            else { continue }

            bands.append(
                Self.band(
                    id: "\(link.from)-\(link.to)",
                    startX: fromFrame.maxX + style.bandInset,
                    startSpan: startSpan,
                    endX: toFrame.minX - style.bandInset,
                    endSpan: endSpan,
                    watts: link.watts,
                    startColor: (colors[link.from] ?? .gray).opacity(Self.bandOpacity),
                    endColor: (colors[link.to] ?? .gray).opacity(Self.bandOpacity)
                )
            )
        }

        for node in graph.nodes {
            guard let frame = frames[node.id] else { continue }
            // A node that splits its power shows the total it splits, as the adapter
            // does when it both charges the battery and runs the MacBook.
            let splits = graph.links.filter { $0.from == node.id }.count > 1
            let fitsValue = frame.height >= style.iconSize * 3
            nodes.append(
                PlacedNode(
                    id: node.id,
                    title: node.title,
                    icon: node.icon,
                    tint: node.tintsIcon ? node.color : nil,
                    frame: frame,
                    valueText: splits && fitsValue ? PowerFlowFormat.compactWatts(node.watts) : nil
                )
            )
        }
    }

    private static func spans(of watts: [Double], in frame: CGRect, style: PowerFlowStyle) -> [ClosedRange<CGFloat>] {
        let heights = distribute(watts, across: frame.height, minimum: style.minimumBandHeight)
        var y = frame.minY
        return heights.map { height in
            defer { y += height }
            return y...(y + height)
        }
    }

    /// Splits `total` in proportion to `values`, but never below a height that still
    /// fits a label, so a tiny flow next to a large one stays legible.
    private static func distribute(_ values: [Double], across total: CGFloat, minimum: CGFloat) -> [CGFloat] {
        guard !values.isEmpty else { return [] }

        let count = CGFloat(values.count)
        let floor = min(minimum, total / count)
        let remaining = total - floor * count
        let sum = values.reduce(0, +)

        return values.map { value in
            let share = sum > 0 ? CGFloat(value / sum) : 1 / count
            return floor + remaining * share
        }
    }

    private static func band(
        id: String,
        startX: CGFloat,
        startSpan: ClosedRange<CGFloat>,
        endX: CGFloat,
        endSpan: ClosedRange<CGFloat>,
        watts: Double,
        startColor: Color,
        endColor: Color
    ) -> Band {
        let controlX = (startX + endX) / 2

        let path = Path { path in
            path.move(to: CGPoint(x: startX, y: startSpan.lowerBound))
            path.addCurve(
                to: CGPoint(x: endX, y: endSpan.lowerBound),
                control1: CGPoint(x: controlX, y: startSpan.lowerBound),
                control2: CGPoint(x: controlX, y: endSpan.lowerBound)
            )
            path.addLine(to: CGPoint(x: endX, y: endSpan.upperBound))
            path.addCurve(
                to: CGPoint(x: startX, y: startSpan.upperBound),
                control1: CGPoint(x: controlX, y: endSpan.upperBound),
                control2: CGPoint(x: controlX, y: startSpan.upperBound)
            )
            path.closeSubpath()
        }

        let startMidY = (startSpan.lowerBound + startSpan.upperBound) / 2
        let endMidY = (endSpan.lowerBound + endSpan.upperBound) / 2

        return Band(
            id: id,
            path: path,
            bounds: path.boundingRect,
            watts: watts,
            labelPosition: CGPoint(x: controlX, y: (startMidY + endMidY) / 2),
            startColor: startColor,
            endColor: endColor
        )
    }
}

#Preview("Charging") {
    let charging = PowerFlowSnapshot(
        adapterWatts: 48.8, batteryWatts: 30.7, cpuWatts: 2.07, displayWatts: 1.51
    )
    let onBattery = PowerFlowSnapshot(
        adapterWatts: 0, batteryWatts: -13.3, cpuWatts: 8.84, displayWatts: 1.51
    )
    VStack(spacing: 24) {
        PowerFlowDiagram(snapshot: charging, style: .menu)
            .frame(width: 292, height: 118)
        PowerFlowDiagram(snapshot: onBattery, style: .menu)
            .frame(width: 292, height: 118)
        PowerFlowDiagram(snapshot: charging, style: .dashboard)
            .frame(width: 700, height: 200)
    }
    .padding()
}
