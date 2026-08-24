import BuddyGrammarKit
import SwiftUI
import UIKit

/// Identifiers and geometry of every key the touch surface owns.
struct KeyboardTouchTargets: Equatable {
    let rects: [String: CGRect]
    let targets: [String: KeyboardInteractionTarget]

    static let empty = KeyboardTouchTargets(rects: [:], targets: [:])
}

/// Raw-touch capture layer for the typing keys.
///
/// SwiftUI DragGestures dispatch key events measurably later than raw touch
/// handling, and thirty-plus per-key recognizers contend on every keystroke.
/// Production keyboards own touches at the UIKit level instead: this view
/// sits over the character keys, hit-tests recorded frames itself, and
/// forwards press/move/release straight into ``KeyboardPointerInteraction``.
///
/// Keys without a registered rect (shift, return, 123, globe, emoji) fall
/// through to their SwiftUI buttons because `hitTest` returns nil there.
final class KeyboardTouchSurfaceView: UIView {
    var configuration = KeyboardTouchTargets.empty
    weak var interaction: KeyboardPointerInteraction?

    private static let hitPadding = UIEdgeInsets(top: 3, left: 4, bottom: 3, right: 4)

    private var activeGestureID: UUID?
    private var activeTouch: UITouch?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard capturedID(at: point) != nil else { return nil }
        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        // Single-pointer semantics match the interaction owner: an in-flight
        // key finishes before another touch may begin.
        guard activeGestureID == nil,
              activeTouch == nil,
              let touch = touches.first else {
            return
        }
        let location = captureLocation(for: touch)
        guard let id = location.flatMap({ capturedID(at: $0) }),
              let point = location,
              let target = configuration.targets[id] else {
            return
        }
        let token = UUID()
        activeGestureID = token
        activeTouch = touch
        interaction?.press(target: target, at: point, gestureID: token)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let token = activeGestureID,
              let touch = activeTouch,
              touches.contains(touch),
              let location = captureLocation(for: touch) else {
            return
        }
        interaction?.move(to: location, gestureID: token)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let token = activeGestureID,
              let touch = activeTouch else {
            return
        }
        defer { resetActiveGesture() }
        guard touches.contains(touch),
              let location = captureLocation(for: touch) else {
            interaction?.cancel(gestureID: token)
            return
        }
        interaction?.release(at: location, gestureID: token)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        guard let token = activeGestureID,
              let touch = activeTouch,
              touches.contains(touch) else {
            return
        }
        resetActiveGesture()
        interaction?.cancel(gestureID: token)
    }

    /// A layout change invalidates the frames an in-flight gesture was
    /// measured against; drop it rather than commit on stale geometry.
    func cancelActiveGestureIfAny() {
        guard let token = activeGestureID else { return }
        resetActiveGesture()
        interaction?.cancel(gestureID: token)
    }

    private func resetActiveGesture() {
        activeGestureID = nil
        activeTouch = nil
    }

    private func captureLocation(for touch: UITouch) -> CGPoint? {
        let location = touch.location(in: self)
        // Swipes may travel slightly past the surface while the gesture is
        // still owned by the initially pressed key.
        guard bounds.insetBy(dx: -24, dy: -12).contains(location) else { return nil }
        return location
    }

    private static func expandedRect(_ rect: CGRect) -> CGRect {
        rect.inset(by: UIEdgeInsets(
            top: -hitPadding.top,
            left: -hitPadding.left,
            bottom: -hitPadding.bottom,
            right: -hitPadding.right
        ))
    }

    private func capturedID(at point: CGPoint) -> String? {
        for (id, rect) in configuration.rects
        where Self.expandedRect(rect).contains(point) {
            return id
        }
        return nil
    }
}

struct KeyboardTouchSurface: UIViewRepresentable {
    let interaction: KeyboardPointerInteraction
    let targets: KeyboardTouchTargets

    func makeUIView(context: Context) -> KeyboardTouchSurfaceView {
        let view = KeyboardTouchSurfaceView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.isMultipleTouchEnabled = false
        view.interaction = interaction
        view.configuration = targets
        return view
    }

    func updateUIView(_ uiView: KeyboardTouchSurfaceView, context: Context) {
        uiView.interaction = interaction
        if uiView.configuration != targets {
            if targets == .empty {
                uiView.cancelActiveGestureIfAny()
            }
            uiView.configuration = targets
        }
    }
}
