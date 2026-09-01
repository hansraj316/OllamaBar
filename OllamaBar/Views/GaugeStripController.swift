import AppKit
import SwiftUI

/// Hosts `GaugeStripView` in a borderless, non-activating floating panel pinned to
/// the right edge of the main screen. The panel sizes itself to its SwiftUI content
/// and can be dragged anywhere by its background.
@MainActor
final class GaugeStripController {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(viewModel: AppViewModel) {
        if panel == nil { panel = makePanel(viewModel: viewModel) }
        guard let panel, !panel.isVisible else { return }
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(viewModel: AppViewModel) -> NSPanel {
        let host = NSHostingView(rootView: GaugeStripView().environment(viewModel))
        host.sizingOptions = [.preferredContentSize]

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width, y: visible.midY - size.height / 2))
    }
}
