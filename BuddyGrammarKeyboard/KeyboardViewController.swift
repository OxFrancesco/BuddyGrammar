import BuddyGrammarKit
import SwiftUI
import UIKit

@MainActor
final class KeyboardControllerBridge {
    weak var controller: UIInputViewController?

    init(controller: UIInputViewController? = nil) {
        self.controller = controller
    }

    func handleInputModeList(from view: UIView, with event: UIEvent) {
        controller?.handleInputModeList(from: view, with: event)
    }
}

@MainActor
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private lazy var controllerBridge = KeyboardControllerBridge(controller: self)
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var documentGeneration: UInt64 = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        primaryLanguage = "en-US"
        hasDictationKey = false

        let rootView = KeyboardRootView(model: model, controllerBridge: controllerBridge)
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController

        let preferredHeight = view.heightAnchor.constraint(equalToConstant: 302)
        preferredHeight.priority = .defaultHigh
        preferredHeight.isActive = true

        model.connect(delegate: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refreshAvailability()
    }

    override func viewWillDisappear(_ animated: Bool) {
        model.deactivate()
        super.viewWillDisappear(animated)
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        documentGeneration &+= 1
        model.documentContextDidChange()
    }

    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput)
        documentGeneration &+= 1
        model.documentContextDidChange()
    }
}

extension KeyboardViewController: KeyboardModelDelegate {
    var keyboardHasFullAccess: Bool {
        hasFullAccess
    }

    func insertText(_ text: String) {
        documentGeneration &+= 1
        textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        documentGeneration &+= 1
        textDocumentProxy.deleteBackward()
    }

    func captureCorrectionSnapshot() -> DocumentCorrectionSnapshot? {
        let proxy = textDocumentProxy
        let identifier = proxy.documentIdentifier as UUID
        let before = proxy.documentContextBeforeInput
        let selected = proxy.selectedText
        let after = proxy.documentContextAfterInput

        if let selected {
            guard let candidate = TextCorrectionCandidate(capturedText: selected) else {
                return nil
            }
            return DocumentCorrectionSnapshot(
                documentIdentifier: identifier,
                generation: documentGeneration,
                contextBeforeInput: before,
                selectedText: selected,
                contextAfterInput: after,
                target: .selection,
                candidate: candidate
            )
        }

        guard let before,
              let candidate = TextContextExtractor.precedingSentence(from: before) else {
            return nil
        }

        return DocumentCorrectionSnapshot(
            documentIdentifier: identifier,
            generation: documentGeneration,
            contextBeforeInput: before,
            selectedText: selected,
            contextAfterInput: after,
            target: .precedingSentence,
            candidate: candidate
        )
    }

    func applyCorrection(_ replacement: String, to snapshot: DocumentCorrectionSnapshot) -> Bool {
        let proxy = textDocumentProxy
        guard snapshot.generation == documentGeneration,
              proxy.documentIdentifier as UUID == snapshot.documentIdentifier,
              proxy.documentContextBeforeInput == snapshot.contextBeforeInput,
              proxy.selectedText == snapshot.selectedText,
              proxy.documentContextAfterInput == snapshot.contextAfterInput else {
            return false
        }

        documentGeneration &+= 1
        switch snapshot.target {
        case .selection:
            proxy.insertText(replacement)
        case .precedingSentence:
            for _ in snapshot.candidate.capturedText {
                proxy.deleteBackward()
            }
            proxy.insertText(replacement)
        }
        return true
    }
}
