import SwiftUI

struct BatteryIndicatorView: View {
    let batteryLevel: Int
    let chargingMode: ChargingMode
    var isLowPowerModeEnabled: Bool = false
    var style: StatusIconStyle = .macOS26Colored
    var showPercentageNextToIcon: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private enum Layout {
        static let bodyHeight: CGFloat = 12
        static let outlinedBodyWidth: CGFloat = 23
        static let filledBodyWidth: CGFloat = 24
        static let outlineCornerRadius: CGFloat = 3.5
        static let filledCornerRadius: CGFloat = 4
        static let outlineWidth: CGFloat = 1
        static let levelHorizontalInset: CGFloat = 2
        static let levelVerticalInset: CGFloat = 1.5
        static let levelCornerRadius: CGFloat = 1.5
        static let terminalGap: CGFloat = 0.5
        static let statusPlugOffset: CGFloat = 2.75
        static let statusStateSlotOffset: CGFloat = 11.6
        static let statusStateSlotWidth: CGFloat = 6
        static let logoSymbolName = "bolt.circle"
        static let levelAnimation: Animation = .easeInOut(duration: 0.25)
    }

    var body: some View {
        HStack(spacing: 4) {
            if showPercentageNextToIcon && style.supportsPercentageNextToIcon {
                Text("\(batteryLevel)%")
                    .font(.system(size: 11))
                    .monospacedDigit()
            }

            icon
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var palette: BatteryPalette {
        BatteryPalette(colorScheme: colorScheme)
    }

    private var levelFraction: CGFloat {
        CGFloat(min(max(batteryLevel, 0), 100)) / 100
    }

    private var alertColor: Color? {
        if batteryLevel <= 20 { return .red }
        if isLowPowerModeEnabled { return .yellow }
        if chargingMode == .charging { return .green }
        return nil
    }

    private var levelColor: Color {
        switch style {
        case .macOS26Colored:
            return alertColor ?? (chargingMode == .pluggedIn ? BatteryPalette.pluggedInBlue : palette.solid)
        case .iOSNative:
            return alertColor ?? palette.solid
        case .hidden, .logo, .status, .macOS26, .macOS27:
            return palette.solid
        }
    }

    private var inkColor: Color {
        levelColor == .yellow ? .black : palette.ink
    }

    private var accessibilityDescription: String {
        var parts = ["Battery \(batteryLevel) percent"]
        switch chargingMode {
        case .charging: parts.append("charging")
        case .pluggedIn: parts.append("plugged in")
        case .discharging: break
        }
        if isLowPowerModeEnabled { parts.append("low power mode") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var icon: some View {
        switch style {
        case .hidden:
            EmptyView()
        case .logo:
            Image(systemName: Layout.logoSymbolName)
                .font(.system(size: 14))
        case .status:
            HStack(spacing: Layout.terminalGap) {
                statusBody
                BatteryTerminal(color: palette.solid, width: 1.5, height: 4.5)
            }
        case .macOS26, .macOS26Colored:
            HStack(spacing: Layout.terminalGap) {
                outlinedBody
                BatteryTerminal(color: palette.dimmed, width: 1, height: 4)
            }
        case .macOS27, .iOSNative:
            HStack(spacing: Layout.terminalGap) {
                filledBody
                BatteryTerminal(color: palette.terminal, width: 1.5, height: 4.5)
            }
        }
    }

    // MARK: Status

    /// Shows what the charger is doing rather than how full the battery is; the
    /// level only appears while discharging, when there is no charger state.
    private var statusBody: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Layout.outlineCornerRadius, style: .continuous)
                .strokeBorder(palette.solid, lineWidth: Layout.outlineWidth)

            if chargingMode == .discharging {
                levelBar(color: palette.solid, bodyWidth: Layout.outlinedBodyWidth)
            } else {
                KnockoutGlyph(shape: PlugShape(), color: palette.solid)
                    .frame(width: Layout.bodyHeight * PlugShape.aspectRatio, height: Layout.bodyHeight)
                    .offset(x: Layout.statusPlugOffset)
                statusStateGlyph
                    .frame(width: Layout.statusStateSlotWidth, height: Layout.bodyHeight)
                    .offset(x: Layout.statusStateSlotOffset)

                // The plug's cable joins the bottom edge, so only the prongs should cut the outline.
                RoundedRectangle(cornerRadius: Layout.outlineCornerRadius, style: .continuous)
                    .strokeBorder(palette.solid, lineWidth: Layout.outlineWidth)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: Layout.bodyHeight / 2)
                    }
            }
        }
        .frame(width: Layout.outlinedBodyWidth, height: Layout.bodyHeight)
        .compositingGroup()
    }

    @ViewBuilder
    private var statusStateGlyph: some View {
        if chargingMode == .charging {
            BoltShape()
                .fill(palette.solid)
                .frame(width: 8 * BoltShape.aspectRatio, height: 8)
        } else {
            HStack(spacing: 1.5) {
                Capsule().frame(width: 1.75, height: 7)
                Capsule().frame(width: 1.75, height: 7)
            }
            .foregroundStyle(palette.solid)
        }
    }

    // MARK: macOS 26

    private var outlinedBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Layout.outlineCornerRadius, style: .continuous)
                .strokeBorder(palette.dimmed, lineWidth: Layout.outlineWidth)

            levelBar(color: levelColor, bodyWidth: Layout.outlinedBodyWidth)

            switch chargingMode {
            case .charging:
                KnockoutGlyph(shape: BoltShape(), color: palette.solid)
                    .frame(width: 11 * BoltShape.aspectRatio, height: 11)
            case .pluggedIn:
                KnockoutGlyph(shape: PlugShape(), color: palette.solid)
                    .frame(width: Layout.bodyHeight * PlugShape.aspectRatio, height: Layout.bodyHeight)
            case .discharging:
                EmptyView()
            }
        }
        .frame(width: Layout.outlinedBodyWidth, height: Layout.bodyHeight)
        .compositingGroup()
    }

    private func levelBar(color: Color, bodyWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Layout.levelCornerRadius, style: .continuous)
            .fill(color)
            .frame(width: (bodyWidth - Layout.levelHorizontalInset * 2) * levelFraction)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Layout.levelHorizontalInset)
            .padding(.vertical, Layout.levelVerticalInset)
            .animation(Layout.levelAnimation, value: batteryLevel)
    }

    // MARK: macOS 27 / iOS

    private var filledBody: some View {
        let isIOS = style == .iOSNative
        let glyphHeight: CGFloat = isIOS ? 8 : 7.5
        let digitFontSize: CGFloat = isIOS ? 10 : 9.5
        let digitCapHeight = NSFont.systemFont(ofSize: digitFontSize, weight: .semibold).capHeight

        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(palette.track)

            Rectangle()
                .fill(levelColor)
                .frame(width: Layout.filledBodyWidth * levelFraction)
                .animation(Layout.levelAnimation, value: batteryLevel)

            HStack(alignment: .digitCenter, spacing: 1) {
                Text(verbatim: "\(batteryLevel)")
                    .font(.system(size: digitFontSize, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    // Text centers its line box, which keeps room for descenders that
                    // digits never use, so the digits would sit high in the body.
                    // Centering on the cap height centers the glyphs themselves.
                    .alignmentGuide(.digitCenter) { dimensions in
                        dimensions[.firstTextBaseline] - digitCapHeight / 2
                    }

                switch chargingMode {
                case .charging:
                    BoltShape()
                        .frame(width: glyphHeight * BoltShape.aspectRatio, height: glyphHeight)
                case .pluggedIn:
                    PlugShape()
                        .frame(width: glyphHeight * PlugShape.aspectRatio, height: glyphHeight)
                case .discharging:
                    EmptyView()
                }
            }
            .foregroundStyle(inkColor)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: Alignment(horizontal: .center, vertical: .digitCenter)
            )
        }
        .frame(width: Layout.filledBodyWidth, height: Layout.bodyHeight)
        .clipShape(RoundedRectangle(cornerRadius: Layout.filledCornerRadius, style: .continuous))
    }
}

private extension VerticalAlignment {
    /// Defaults to the view's center, so a frame aligned on it puts a child's digit
    /// center on the frame's center line.
    private enum DigitCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let digitCenter = VerticalAlignment(DigitCenter.self)
}

/// Opaque colors, so the icon reads the same over any menu bar tint or button fill.
private struct BatteryPalette {
    static let pluggedInBlue = Color(red: 0.53, green: 0.69, blue: 0.95)

    let solid: Color
    let ink: Color
    let track: Color
    let terminal: Color
    let dimmed: Color

    init(colorScheme: ColorScheme) {
        let isDark = colorScheme == .dark
        solid = isDark ? .white : .black
        ink = isDark ? Color(white: 0.14) : .white
        track = isDark ? Color(white: 0.76) : Color(white: 0.6)
        terminal = isDark ? Color(white: 0.7) : Color(white: 0.55)
        dimmed = solid.opacity(0.35)
    }
}

private struct BatteryTerminal: View {
    let color: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: width * 0.5,
            topTrailingRadius: width * 0.5
        )
        .fill(color)
        .frame(width: width, height: height)
    }
}

/// Cuts a thin gap around the glyph through whatever is drawn beneath it, so a
/// glyph in the same color as the battery fill stays readable. Needs an
/// enclosing compositing group to keep the cut inside the icon.
private struct KnockoutGlyph<GlyphShape: Shape>: View {
    let shape: GlyphShape
    let color: Color

    var body: some View {
        ZStack {
            shape
                .stroke(Color.black, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                .blendMode(.destinationOut)
            shape
                .fill(color)
        }
    }
}

struct PlugShape: Shape {
    static let aspectRatio: CGFloat = 0.58

    nonisolated func path(in rect: CGRect) -> Path {
        let headTop: CGFloat = 0.3
        let shoulder: CGFloat = 0.56
        let neck: CGFloat = 0.73
        let headCorner = rect.width * 0.1
        let prongCorner = rect.width * 0.06
        let shoulderCorner = rect.width * 0.25
        let neckCorner = rect.width * 0.1

        return Path.roundedPolygon(in: rect, vertices: [
            (0, headTop, headCorner),
            (0.2, headTop, 0),
            (0.2, 0, prongCorner),
            (0.4, 0, prongCorner),
            (0.4, headTop, 0),
            (0.6, headTop, 0),
            (0.6, 0, prongCorner),
            (0.8, 0, prongCorner),
            (0.8, headTop, 0),
            (1, headTop, headCorner),
            (1, shoulder, shoulderCorner),
            (0.66, neck, neckCorner),
            (0.66, 1, 0),
            (0.34, 1, 0),
            (0.34, neck, neckCorner),
            (0, shoulder, shoulderCorner),
        ])
    }
}

struct BoltShape: Shape {
    static let aspectRatio: CGFloat = 0.6

    nonisolated func path(in rect: CGRect) -> Path {
        let tipCorner = rect.width * 0.05

        return Path.roundedPolygon(in: rect, vertices: [
            (0.68, 0, tipCorner),
            (0, 0.58, tipCorner),
            (0.44, 0.58, 0),
            (0.32, 1, tipCorner),
            (1, 0.42, tipCorner),
            (0.56, 0.42, 0),
        ])
    }
}

extension Path {
    /// Vertices are in unit space relative to `rect`; each corner radius is in points.
    nonisolated static func roundedPolygon(
        in rect: CGRect,
        vertices: [(x: CGFloat, y: CGFloat, cornerRadius: CGFloat)]
    ) -> Path {
        let points = vertices.map {
            CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height)
        }
        guard let first = points.first, let last = points.last else { return Path() }

        var path = Path()
        // Starting mid-edge lets the first vertex be rounded like the others.
        path.move(to: CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
        for index in points.indices {
            path.addArc(
                tangent1End: points[index],
                tangent2End: points[(index + 1) % points.count],
                radius: vertices[index].cornerRadius
            )
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(StatusIconStyle.allCases.filter { $0 != .hidden }) { style in
            Text(style.rawValue)
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                ForEach([100, 75, 15], id: \.self) { level in
                    BatteryIndicatorView(
                        batteryLevel: level, chargingMode: .discharging, style: style)
                    BatteryIndicatorView(
                        batteryLevel: level, chargingMode: .charging, style: style)
                    BatteryIndicatorView(
                        batteryLevel: level, chargingMode: .pluggedIn, style: style)
                }
            }
        }
    }
    .padding()
    .background(Color(NSColor.windowBackgroundColor))
}
