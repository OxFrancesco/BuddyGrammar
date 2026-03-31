import AppKit
import Foundation

@MainActor
final class EventSimulationService {
    func simulateCopy() throws {
        try postKeyPress(keyCode: 8, modifiers: .maskCommand)
    }

    func simulatePaste() throws {
        try postKeyPress(keyCode: 9, modifiers: .maskCommand)
    }

    private func postKeyPress(keyCode: CGKeyCode, modifiers: CGEventFlags) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            throw RewriteFailure.pasteFailed
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
