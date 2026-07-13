import SwiftUI
import UIKit

struct NextKeyboardButton: UIViewRepresentable {
    let controllerBridge: KeyboardControllerBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(controllerBridge: controllerBridge)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.tintColor = .label
        button.backgroundColor = .systemGray3
        button.layer.cornerRadius = 6
        button.accessibilityLabel = "Next keyboard"
        button.accessibilityHint = "Tap for the next keyboard, or hold to choose a keyboard"
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleInputModeList(_:forEvent:)),
            for: .allTouchEvents
        )
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.controllerBridge = controllerBridge
    }

    @MainActor
    final class Coordinator: NSObject {
        var controllerBridge: KeyboardControllerBridge

        init(controllerBridge: KeyboardControllerBridge) {
            self.controllerBridge = controllerBridge
        }

        @objc func handleInputModeList(_ sender: UIButton, forEvent event: UIEvent) {
            controllerBridge.handleInputModeList(from: sender, with: event)
        }
    }
}
