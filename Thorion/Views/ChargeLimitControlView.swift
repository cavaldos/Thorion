import Defaults
import SwiftUI

struct ChargeLimitControlView: View {
    let viewModel: MenuViewModel
    let openChargingSettings: @MainActor () -> Void

    @Default(.manageCharging) private var manageCharging
    @Default(.chargeLimit) private var chargeLimit
    @Default(.sailingMode) private var sailingMode
    @Default(.sailingModeLimit) private var sailingModeLimit
    @Environment(\.colorScheme) private var colorScheme
    // Committed only on release, so a drag doesn't ask the helper to switch limits at every step.
    @State private var draggedLimit: Int?

    private enum ButtonLabelContent {
        case titleAndIcon
        case title
        case icon
    }

    private enum Layout {
        static let pillHeight: CGFloat = 28
        static let pillHorizontalPadding: CGFloat = 8
        static let iconOnlyPillHorizontalPadding: CGFloat = 5
        static let pillSpacing: CGFloat = 6
        static let buttonIconSize: CGFloat = 17
        static let rowSpacing: CGFloat = 7
        static let noticeButtonHeight: CGFloat = 24
        static let trackHeight: CGFloat = 24
        static let handleWidth: CGFloat = 7
        static let handleHeight: CGFloat = 34
        static let trackTextLeadingPadding: CGFloat = 11
        static let sailingMarkerWidth: CGFloat = 1.5
        static let sailingMarkerOverhang: CGFloat = 1
        // Keeps the charging glyphs readable when the battery fill is too short to hold them.
        static let minimumContentWidth: CGFloat = 120
        static let plugHeight: CGFloat = 18
        static let boltHeight: CGFloat = 14
        static let pauseBarSize = CGSize(width: 3.5, height: 10)
        static let sailSize = CGSize(width: 14, height: 13)
        static let handleAnimation: Animation = .easeOut(duration: 0.12)
    }

    // Top Up charges to full, so the slider shows that while it is on and returns to the
    // saved limit once it is turned off; the saved limit itself is never changed.
    private var displayedLimit: Int {
        if viewModel.chargeLimitOverrideActive {
            return ChargeLimitScale.range.upperBound
        }
        return draggedLimit ?? chargeLimit
    }

    private var isSliderEnabled: Bool {
        manageCharging && !viewModel.chargeLimitOverrideActive
    }
    private var palette: ChargeLimitPalette { ChargeLimitPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: Layout.rowSpacing) {
            // Some translated button titles are too wide for the menu next to their icons.
            ViewThatFits(in: .horizontal) {
                actionRow(buttonLabel: .titleAndIcon)
                actionRow(buttonLabel: .title)
                actionRow(buttonLabel: .icon)
            }
            slider

            if !manageCharging {
                notice(
                    "Charge management is off",
                    buttonTitle: "Turn On…",
                    action: openChargingSettings
                )
            } else if ChargingHelperManager.shared.helperStatus != .installed {
                // Without the helper, the LED and discharge commands fail silently.
                notice(
                    "Charging helper is not allowed",
                    buttonTitle: "Allow…",
                    action: { ChargingHelperManager.shared.openLoginItemsSettings() }
                )
            } else if !ChargingHelperManager.shared.isResponding {
                // Registered but not starting, usually because the app was rebuilt or
                // updated since the helper was registered.
                notice(
                    "Charging helper is not responding",
                    buttonTitle: "Repair",
                    action: { Task { await ChargingHelperManager.shared.repair() } }
                )
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: Actions

    private func actionRow(buttonLabel: ButtonLabelContent) -> some View {
        HStack(spacing: Layout.pillSpacing) {
            Text("**Limit:** \(displayedLimit)%")
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, Layout.pillHorizontalPadding)
                .frame(height: Layout.pillHeight)
                .background(Capsule().fill(palette.surface))
                .fixedSize()
                .opacity(manageCharging ? 1 : PillButtonStyle.disabledOpacity)

            Spacer(minLength: 0)

            actionButton(
                "Discharge",
                systemImage: "minus.circle",
                isActive: viewModel.forceDischargeActive,
                content: buttonLabel,
                action: { viewModel.toggleForceDischarge() }
            )
            .disabled(!manageCharging || !viewModel.adapterConnected || viewModel.chargeLimitOverrideActive
                || !viewModel.canForceDischarge)

            actionButton(
                "Top Up",
                systemImage: "plus.circle",
                isActive: viewModel.chargeLimitOverrideActive,
                content: buttonLabel,
                action: { viewModel.toggleChargeLimitOverride() }
            )
            .disabled(!manageCharging || !viewModel.adapterConnected || viewModel.forceDischargeActive
                || !viewModel.canTopUp)
        }
    }

    private func actionButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        isActive: Bool,
        content: ButtonLabelContent,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if content != .icon {
                    Text(title)
                        .lineLimit(1)
                }
                if content != .title {
                    Image(systemName: systemImage)
                        .font(.system(size: Layout.buttonIconSize))
                }
            }
            .padding(
                .horizontal,
                content == .icon ? Layout.iconOnlyPillHorizontalPadding : Layout.pillHorizontalPadding
            )
            .frame(height: Layout.pillHeight)
            .fixedSize()
        }
        .buttonStyle(PillButtonStyle(fill: isActive ? palette.accent : palette.surface, isActive: isActive))
        .help(title)
        .accessibilityLabel(Text(title))
    }

    private func notice(
        _ message: LocalizedStringKey,
        buttonTitle: LocalizedStringKey,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: action) {
                Text(buttonTitle)
                    .lineLimit(1)
                    .padding(.horizontal, Layout.pillHorizontalPadding)
                    .frame(height: Layout.noticeButtonHeight)
                    .fixedSize()
            }
            .buttonStyle(PillButtonStyle(fill: palette.accent, isActive: true))
        }
    }

    // MARK: Slider

    private var slider: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let limitPosition = position(of: displayedLimit, trackWidth: trackWidth)
            let fillWidth = max(position(of: viewModel.displayPercentage, trackWidth: trackWidth), Layout.trackHeight)
            let contentWidth = min(max(fillWidth, Layout.minimumContentWidth), trackWidth)

            ZStack(alignment: .leading) {
                Capsule().fill(palette.surface)
                    .frame(height: Layout.trackHeight)

                Capsule().fill(palette.accent)
                    .frame(width: fillWidth, height: Layout.trackHeight)
                    .animation(Layout.handleAnimation, value: viewModel.displayPercentage)

                // Drawn twice so the text stays readable both on the fill and on the
                // empty track: primary everywhere, white where it overlaps the fill.
                trackContent(width: contentWidth)
                    .foregroundStyle(.primary)
                trackContent(width: contentWidth)
                    .foregroundStyle(.white)
                    .mask(alignment: .leading) {
                        Capsule().frame(width: fillWidth, height: Layout.trackHeight)
                    }

                if let sailingThreshold {
                    sailingMarker(threshold: sailingThreshold)
                        .offset(x: position(of: sailingThreshold, trackWidth: trackWidth) - Layout.sailingMarkerWidth / 2)
                }

                handle
                    .offset(x: limitPosition - Layout.handleWidth / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        draggedLimit = limit(at: value.location.x, trackWidth: trackWidth)
                    }
                    .onEnded { value in
                        let newLimit = limit(at: value.location.x, trackWidth: trackWidth)
                        if newLimit != chargeLimit {
                            chargeLimit = newLimit
                        }
                        draggedLimit = nil
                    },
                including: isSliderEnabled ? .all : .none
            )
            .animation(Layout.handleAnimation, value: displayedLimit)
        }
        .frame(height: Layout.handleHeight)
        .opacity(manageCharging ? 1 : PillButtonStyle.disabledOpacity)
        .disabled(!isSliderEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Charge limit"))
        .accessibilityValue(Text(verbatim: "\(displayedLimit)%"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                chargeLimit = ChargeLimitScale.snapped(Double(chargeLimit + ChargeLimitScale.step))
            case .decrement:
                chargeLimit = ChargeLimitScale.snapped(Double(chargeLimit - ChargeLimitScale.step))
            @unknown default:
                break
            }
        }
    }

    private func position(of percentage: Int, trackWidth: CGFloat) -> CGFloat {
        trackWidth * CGFloat(min(max(percentage, 0), 100)) / 100
    }

    private func limit(at location: CGFloat, trackWidth: CGFloat) -> Int {
        guard trackWidth > 0 else { return chargeLimit }
        return ChargeLimitScale.snapped(Double(location / trackWidth * 100))
    }

    private func trackContent(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Text(verbatim: "\(viewModel.displayPercentage)%")
                .monospacedDigit()
                .lineLimit(1)
                .padding(.leading, Layout.trackTextLeadingPadding)

            chargingStateGlyphs
                .frame(maxWidth: .infinity)
        }
        .frame(width: width, height: Layout.trackHeight, alignment: .leading)
    }

    private var chargingStateGlyphs: some View {
        HStack(spacing: 12) {
            switch viewModel.chargingMode {
            case .charging:
                HStack(spacing: 2.5) {
                    plugGlyph
                    BoltShape()
                        .frame(width: Layout.boltHeight * BoltShape.aspectRatio, height: Layout.boltHeight)
                }
            case .pluggedIn:
                HStack(spacing: 2.5) {
                    plugGlyph
                    HStack(spacing: 3) {
                        pauseBar
                        pauseBar
                    }
                }
            case .discharging:
                EmptyView()
            }

            if viewModel.isSailing {
                SailShape()
                    .frame(width: Layout.sailSize.width, height: Layout.sailSize.height)
            }
        }
    }

    private var plugGlyph: some View {
        PlugShape()
            .frame(width: Layout.plugHeight * PlugShape.aspectRatio, height: Layout.plugHeight)
    }

    private var pauseBar: some View {
        RoundedRectangle(cornerRadius: 1)
            .frame(width: Layout.pauseBarSize.width, height: Layout.pauseBarSize.height)
    }

    /// Charging resumes once the battery drops below this. Hidden during Top Up, which
    /// charges to full regardless.
    private var sailingThreshold: Int? {
        guard manageCharging, sailingMode, !viewModel.chargeLimitOverrideActive else { return nil }
        return displayedLimit - sailingModeLimit
    }

    private func sailingMarker(threshold: Int) -> some View {
        let height = Layout.trackHeight + Layout.sailingMarkerOverhang * 2
        let inset = Layout.sailingMarkerWidth / 2
        let isOnFill = threshold <= viewModel.displayPercentage

        return Path { path in
            path.move(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: inset, y: height - inset))
        }
        .stroke(
            isOnFill ? ChargeLimitPalette.markerOnFill : palette.markerOnTrack,
            style: StrokeStyle(lineWidth: Layout.sailingMarkerWidth, lineCap: .round, dash: [2.25, 5.5])
        )
        .frame(width: Layout.sailingMarkerWidth, height: height)
    }

    private var handle: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [palette.handleTop, palette.handleBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Capsule().strokeBorder(palette.handleBorder, lineWidth: 0.5)
            }
            .frame(width: Layout.handleWidth, height: Layout.handleHeight)
            .shadow(color: .black.opacity(0.35), radius: 2)
    }
}

private struct ChargeLimitPalette {
    static let markerOnFill = Color.white.opacity(0.6)

    let surface: Color
    let accent = Color(red: 0.24, green: 0.44, blue: 0.6)
    let handleTop: Color
    let handleBottom: Color
    let handleBorder: Color
    let markerOnTrack: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            surface = .white.opacity(0.2)
            handleTop = Color(white: 0.89)
            handleBottom = Color(white: 0.77)
            handleBorder = .clear
            markerOnTrack = .white.opacity(0.6)
        } else {
            surface = .black.opacity(0.08)
            handleTop = .white
            handleBottom = Color(white: 0.94)
            handleBorder = .black.opacity(0.15)
            markerOnTrack = .black.opacity(0.35)
        }
    }
}

private struct PillButtonStyle: ButtonStyle {
    static let disabledOpacity: CGFloat = 0.4

    let fill: Color
    let isActive: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : Self.disabledOpacity)
    }
}

private struct SailShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let corner = rect.width * 0.04
        var path = Path.roundedPolygon(in: rect, vertices: [
            (0.375, 0, corner),
            (0.54, 0.42, corner),
            (0.02, 1, corner),
        ])
        path.addPath(Path.roundedPolygon(in: rect, vertices: [
            (0.57, 0.44, corner),
            (1, 0.62, corner),
            (0.1, 1, corner),
        ]))
        return path
    }
}
