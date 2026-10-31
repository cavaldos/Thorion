import AppKit
import Defaults
import SwiftUI

@MainActor
class StatusBarManager {
    private let statusItem: NSStatusItem
    private let viewModel: MenuViewModel
    private var styleObservation: Task<Void, Never>?

    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        setupPersistentHostingView()
        observeIconStyle()
    }

    deinit {
        MainActor.assumeIsolated {
            styleObservation?.cancel()
        }
    }

    private func observeIconStyle() {
        styleObservation = Task { [weak self] in
            for await style in Defaults.updates(.statusIconStyle) {
                self?.statusItem.isVisible = style != .hidden
            }
        }
    }

    func setMenu(_ menu: NSMenu) {
        statusItem.menu = menu
    }

    private func setupPersistentHostingView() {
        guard let button = statusItem.button else { return }

        let rootView = StatusBarContentView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: rootView)

        button.subviews.forEach { $0.removeFromSuperview() }
        button.title = ""
        button.image = nil

        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: button.topAnchor, constant: 4),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -4),
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 7),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -7),
        ])
    }
}

struct StatusBarContentView: View {
    let viewModel: MenuViewModel
    @Default(.statusIconStyle) var style
    @Default(.showPercentageNextToIcon) var showPercentageNextToIcon

    var body: some View {
        BatteryIndicatorView(
            batteryLevel: viewModel.displayPercentage,
            chargingMode: viewModel.chargingMode,
            isLowPowerModeEnabled: viewModel.isLowPowerModeEnabled,
            style: style,
            showPercentageNextToIcon: showPercentageNextToIcon
        )
        .fixedSize()
    }
}
