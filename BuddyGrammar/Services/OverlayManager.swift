import AppKit
import SwiftUI

@MainActor
final class OverlayManager {
    private let model: OverlayModel
    private var panel: NSPanel?

    init(model: OverlayModel) {
        self.model = model
    }

    func present(_ phase: OverlayPhase, motionMode: OverlayMotionMode) {
        let panel = ensurePanel(motionMode: motionMode)
        updatePosition(for: panel)
        model.present(phase)
        panel.orderFrontRegardless()
    }

    func dismiss(after delay: Duration? = nil) {
        Task { @MainActor in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            model.hide()
            panel?.orderOut(nil)
        }
    }

    private func ensurePanel(motionMode: OverlayMotionMode) -> NSPanel {
        if let panel {
            if let hostingController = panel.contentViewController as? NSHostingController<OverlayView> {
                hostingController.rootView = OverlayView(model: model, motionMode: motionMode)
            }
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentViewController = NSHostingController(rootView: OverlayView(model: model, motionMode: motionMode))
        self.panel = panel
        return panel
    }

    private func updatePosition(for panel: NSPanel) {
        let targetScreen = NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen = targetScreen else { return }
        let width: CGFloat = 360
        let height: CGFloat = 92
        let x = screen.frame.midX - (width / 2)
        let y = screen.frame.maxY - height - 12
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}
