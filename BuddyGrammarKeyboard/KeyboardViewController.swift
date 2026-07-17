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

    /// True only on devices where the system does not already provide a
    /// keyboard switcher, in which case Apple requires the keyboard to show
    /// its own globe key.
    var needsInputModeSwitchKey: Bool {
        controller?.needsInputModeSwitchKey ?? false
    }
}

@MainActor
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private lazy var controllerBridge = KeyboardControllerBridge(controller: self)
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?
    private var documentGeneration: UInt64 = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        primaryLanguage = Locale.preferredLanguages.first ?? "en-US"
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

        let heightConstraint = view.heightAnchor.constraint(
            equalToConstant: preferredKeyboardHeight(for: view.bounds.size)
        )
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
        self.heightConstraint = heightConstraint

        registerForTraitChanges([UITraitVerticalSizeClass.self, UITraitHorizontalSizeClass.self]) {
            (controller: KeyboardViewController, _: UITraitCollection) in
            controller.updatePreferredHeight()
        }

        model.connect(delegate: self)
        let lexiconCompletion: @Sendable (UILexicon) -> Void = { [weak self] lexicon in
            Task { @MainActor [weak self] in
                self?.model.updateSupplementaryLexicon(lexicon)
            }
        }
        requestSupplementaryLexicon(completion: lexiconCompletion)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePreferredHeight()
        model.activate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        model.deactivate()
        super.viewWillDisappear(animated)
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        heightConstraint?.constant = preferredKeyboardHeight(for: size)
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

    private func updatePreferredHeight() {
        heightConstraint?.constant = preferredKeyboardHeight(for: view.bounds.size)
    }

    private func preferredKeyboardHeight(for size: CGSize) -> CGFloat {
        if traitCollection.userInterfaceIdiom == .pad {
            return 330
        }
        let referenceSize = size == .zero ? view.window?.bounds.size ?? size : size
        let isLandscape = traitCollection.verticalSizeClass == .compact
            || referenceSize.width > referenceSize.height && referenceSize.height > 0
        return isLandscape ? 220 : 302
    }
}

extension KeyboardViewController: KeyboardModelDelegate {
    var keyboardHasFullAccess: Bool {
        hasFullAccess
    }

    var contextBeforeInput: String? {
        textDocumentProxy.documentContextBeforeInput
    }

    var keyboardLanguage: String {
        primaryLanguage ?? Locale.preferredLanguages.first ?? "en-US"
    }

    var allowsAutomaticTextCorrection: Bool {
        let proxy = textDocumentProxy
        guard proxy.autocorrectionType != .no,
              proxy.spellCheckingType != .no,
              proxy.isSecureTextEntry != true else {
            return false
        }

        switch proxy.keyboardType {
        case .URL, .emailAddress, .phonePad, .namePhonePad,
             .numberPad, .decimalPad, .asciiCapableNumberPad:
            return false
        default:
            break
        }

        guard let contentType = proxy.textContentType ?? nil else { return true }
        return !Self.correctionSensitiveContentTypes.contains(contentType)
    }

    var allowsPersonalizedLearning: Bool {
        // iOS already replaces custom keyboards in secure fields. Mirror the
        // stricter correction policy as defense in depth for structured,
        // identity, contact, and credential fields.
        allowsAutomaticTextCorrection
    }

    private static let correctionSensitiveContentTypes: [UITextContentType] = [
        .URL,
        .emailAddress,
        .telephoneNumber,
        .name,
        .givenName,
        .middleName,
        .familyName,
        .namePrefix,
        .nameSuffix,
        .nickname,
        .organizationName,
        .username,
        .password,
        .newPassword,
        .oneTimeCode,
        .creditCardNumber,
    ]

    func insertText(_ text: String) {
        documentGeneration &+= 1
        textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        documentGeneration &+= 1
        textDocumentProxy.deleteBackward()
    }

    func openHostApplication(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector), !(current is UIInputViewController) {
                current.perform(selector, with: url)
                return true
            }
            responder = current.next
        }
        return false
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

        // No selection: keep the explicit correction request scoped to the
        // active sentence. This matches the UI promise and minimizes text
        // sent for cloud processing.
        guard let sentence = TextContextExtractor.currentSentence(
            contextBeforeCursor: before ?? "",
            contextAfterCursor: after ?? ""
        ) else {
            return nil
        }

        return DocumentCorrectionSnapshot(
            documentIdentifier: identifier,
            generation: documentGeneration,
            contextBeforeInput: before,
            selectedText: selected,
            contextAfterInput: after,
            target: .currentSentence(
                charactersAfterCursor: sentence.textAfterCursor.utf16.count
            ),
            candidate: sentence.candidate
        )
    }

    func applyCorrection(
        _ replacement: String,
        to snapshot: DocumentCorrectionSnapshot
    ) -> AppliedCorrection? {
        let proxy = textDocumentProxy
        guard snapshot.generation == documentGeneration,
              proxy.documentIdentifier as UUID == snapshot.documentIdentifier,
              proxy.documentContextBeforeInput == snapshot.contextBeforeInput,
              proxy.selectedText == snapshot.selectedText,
              proxy.documentContextAfterInput == snapshot.contextAfterInput else {
            return nil
        }

        documentGeneration &+= 1
        switch snapshot.target {
        case .selection:
            proxy.insertText(replacement)
        case .currentSentence(let charactersAfterCursor):
            if charactersAfterCursor > 0 {
                // Move to the end of the sentence before replacing the
                // bounded captured range.
                proxy.adjustTextPosition(byCharacterOffset: charactersAfterCursor)
            }
            for _ in snapshot.candidate.capturedText {
                proxy.deleteBackward()
            }
            proxy.insertText(replacement)
        }

        return AppliedCorrection(
            documentIdentifier: proxy.documentIdentifier as UUID,
            contextBeforeInput: proxy.documentContextBeforeInput,
            selectedText: proxy.selectedText,
            contextAfterInput: proxy.documentContextAfterInput,
            originalText: snapshot.candidate.capturedText,
            replacementText: replacement
        )
    }

    func canUndoCorrection(_ correction: AppliedCorrection) -> Bool {
        let proxy = textDocumentProxy
        return proxy.documentIdentifier as UUID == correction.documentIdentifier
            && proxy.documentContextBeforeInput == correction.contextBeforeInput
            && proxy.selectedText == correction.selectedText
            && proxy.documentContextAfterInput == correction.contextAfterInput
    }

    func undoCorrection(_ correction: AppliedCorrection) -> Bool {
        guard canUndoCorrection(correction) else { return false }

        documentGeneration &+= 1
        for _ in correction.replacementText {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(correction.originalText)
        return true
    }
}
