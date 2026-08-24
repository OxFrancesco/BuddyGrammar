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

    func playInputClick() {
        UIDevice.current.playInputClick()
    }
}

@MainActor
final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {
    private let model = KeyboardModel()
    private lazy var controllerBridge = KeyboardControllerBridge(controller: self)
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?
    private var documentGeneration: UInt64 = 0
    private let fallbackEditorFieldIdentifier = UUID().uuidString

    /// UIKit declares `documentIdentifier` as nonnull, but the keyboard proxy can
    /// return Objective-C `nil` while a document is still being attached. Reading
    /// it through the Swift property traps before application code can recover.
    private var currentDocumentIdentifier: UUID? {
        (textDocumentProxy as? NSObject)?.value(forKey: "documentIdentifier") as? UUID
    }

    var enableInputClicksWhenVisible: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        primaryLanguage = Locale.preferredLanguages.first ?? "en-US"
        hasDictationKey = false
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()

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

    /// The keyboard spans the full screen width, so its outermost keys sit on
    /// the system screen-edge gesture zones. iOS otherwise holds touches near
    /// those edges (Q, A, Z, shift, delete, return) while deciding whether the
    /// user is performing an edge swipe, which shows up as dropped or
    /// second-late keystrokes on real devices.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        [.left, .right]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        updatePreferredHeight()
        model.activate()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        unlockWindowTouchDelivery()
    }

    override func viewWillDisappear(_ animated: Bool) {
        model.deactivate()
        super.viewWillDisappear(animated)
    }

    /// Window-level system gesture recognizers (the app-switcher and
    /// notification gates) delay touch delivery to the keyboard while they
    /// disambiguate. They never claim these touches from a keyboard, so the
    /// delay is pure latency on every keystroke; opting them out is the
    /// documented remedy for edge keys that respond a beat late.
    ///
    /// Only the window and its ancestors are touched — the keyboard's own
    /// hosted SwiftUI content keeps its recognizers untouched.
    private func unlockWindowTouchDelivery() {
        guard let window = view.window else { return }
        var systemContainers: [UIView] = [window]
        var next: UIView? = window.superview
        while let current = next {
            systemContainers.append(current)
            next = current.superview
        }
        for container in systemContainers {
            for recognizer in container.gestureRecognizers ?? [] {
                recognizer.delaysTouchesBegan = false
                recognizer.delaysTouchesEnded = false
                if recognizer is UIScreenEdgePanGestureRecognizer {
                    recognizer.isEnabled = false
                }
            }
        }
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

    var contextAfterInput: String? {
        textDocumentProxy.documentContextAfterInput
    }

    var keyboardLanguage: String {
        primaryLanguage ?? Locale.preferredLanguages.first ?? "en-US"
    }

    var editorReturnIntent: String? {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .default:
            return nil
        case .go, .join, .route:
            return "go"
        case .google, .search, .yahoo:
            return "search"
        case .next, .continue:
            return "next"
        case .send:
            return "send"
        case .done, .emergencyCall:
            return "done"
        @unknown default:
            return nil
        }
    }

    var editorFieldIdentifier: String {
        currentDocumentIdentifier?.uuidString ?? fallbackEditorFieldIdentifier
    }

    var editorFieldTraits: EditorFieldTraits {
        let proxy = textDocumentProxy
        let isSecure = proxy.isSecureTextEntry == true
        let suggestionsDisabled = proxy.autocorrectionType == .no
            || proxy.spellCheckingType == .no

        return EditorFieldTraits(
            kind: Self.editorFieldKind(
                keyboardType: proxy.keyboardType ?? .default,
                contentType: proxy.textContentType ?? nil,
                returnKeyType: proxy.returnKeyType ?? .default,
                isSecure: isSecure
            ),
            isSecure: isSecure,
            suggestionsDisabled: suggestionsDisabled,
            personalizedLearningDisabled: suggestionsDisabled,
            autoCapitalization: Self.editorAutoCapitalizationMode(
                proxy.autocapitalizationType ?? .sentences
            )
        )
    }

    private static func editorAutoCapitalizationMode(
        _ type: UITextAutocapitalizationType
    ) -> EditorAutoCapitalizationMode {
        switch type {
        case .none:
            .none
        case .words:
            .words
        case .sentences:
            .sentences
        case .allCharacters:
            .allCharacters
        @unknown default:
            .sentences
        }
    }

    private static func editorFieldKind(
        keyboardType: UIKeyboardType,
        contentType: UITextContentType?,
        returnKeyType: UIReturnKeyType,
        isSecure: Bool
    ) -> EditorFieldKind {
        if isSecure { return .password }
        if contentType == .oneTimeCode { return .oneTimeCode }
        if contentType == .password || contentType == .newPassword { return .password }
        if contentType == .dateTime { return .dateTime }
        if contentType == .URL { return .url }
        if contentType == .emailAddress { return .emailAddress }
        if contentType == .telephoneNumber { return .phoneNumber }
        if contentType == .creditCardNumber { return .number }
        if contentType == .flightNumber || contentType == .shipmentTrackingNumber {
            return .code
        }
        if let contentType, identityContentTypes.contains(contentType) {
            return .personName
        }
        if returnKeyType == .search { return .search }

        switch keyboardType {
        case .URL:
            return .url
        case .emailAddress:
            return .emailAddress
        case .phonePad:
            return .phoneNumber
        case .namePhonePad:
            return .personName
        case .numberPad, .asciiCapableNumberPad:
            return .number
        case .decimalPad:
            return .decimal
        case .webSearch:
            return .search
        default:
            return .plainText
        }
    }

    private static let identityContentTypes: [UITextContentType] = [
        .name, .givenName, .middleName, .familyName, .namePrefix,
        .nameSuffix, .nickname, .organizationName, .username,
    ]

    func insertText(_ text: String) {
        documentGeneration &+= 1
        textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        documentGeneration &+= 1
        textDocumentProxy.deleteBackward()
    }

    func moveCursor(byUTF16Offset offset: Int) {
        guard offset != 0 else { return }
        documentGeneration &+= 1
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    func playInputClick() {
        UIDevice.current.playInputClick()
    }

    func openHostApplication(
        _ url: URL,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        guard let extensionContext else {
            completion(openHostApplicationThroughResponderChain(url))
            return
        }
        extensionContext.open(url) { [weak self] didOpen in
            Task { @MainActor in
                guard !didOpen else {
                    completion(true)
                    return
                }
                completion(
                    self?.openHostApplicationThroughResponderChain(url) ?? false
                )
            }
        }
    }

    /// Opens the containing app from the extension. `extensionContext.open`
    /// is Today-widget-only, so this walks the responder chain to the host
    /// process's UIApplication and invokes the *modern* Open URL entry point.
    ///
    /// The legacy `openURL:` selector is force-failed by UIKit since iOS 18
    /// ("BUG IN CLIENT OF UIKIT … Force returning false"), which silently
    /// swallowed earlier handoff attempts. `openURL:options:completionHandler:`
    /// still works when all three arguments are passed explicitly, so the
    /// method implementation is invoked directly through its IMP instead of
    /// `perform`, which cannot supply the third parameter.
    private func openHostApplicationThroughResponderChain(_ url: URL) -> Bool {
        guard let applicationClass = NSClassFromString("UIApplication") else {
            return false
        }
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            // Only the host process's UIApplication owns a real
            // implementation of this selector. Intermediate responders such
            // as UIScene/UIWindowScene merely forward it, and invoking their
            // forwarding stub aborts with an unrecognized-selector crash.
            if current.isKind(of: applicationClass),
               current.responds(to: selector) {
                let implementation = current.method(for: selector)
                typealias OpenURLEntryPoint = @convention(c) (
                    NSObject, Selector, URL, [UIApplication.OpenExternalURLOptionsKey: Any],
                    ((Bool) -> Void)?
                ) -> Void
                let open = unsafeBitCast(implementation, to: OpenURLEntryPoint.self)
                open(current, selector, url, [:], nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    func captureCorrectionSnapshot(
        requestScope: DocumentCorrectionRequestScope
    ) -> DocumentCorrectionSnapshot? {
        let proxy = textDocumentProxy
        guard let identifier = currentDocumentIdentifier else { return nil }
        let before = proxy.documentContextBeforeInput
        let selected = proxy.selectedText
        let after = proxy.documentContextAfterInput

        if requestScope == .currentText, let selected {
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

        if requestScope == .allText {
            guard let allText = TextContextExtractor.allAccessibleText(
                contextBeforeCursor: before ?? "",
                selectedText: selected,
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
                target: .allText(
                    charactersAfterCursor: allText.textAfterCursor.utf16.count
                ),
                candidate: allText.candidate
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
        guard let documentIdentifier = currentDocumentIdentifier,
              snapshot.generation == documentGeneration,
              documentIdentifier == snapshot.documentIdentifier,
              proxy.documentContextBeforeInput == snapshot.contextBeforeInput,
              proxy.selectedText == snapshot.selectedText,
              proxy.documentContextAfterInput == snapshot.contextAfterInput else {
            return nil
        }

        documentGeneration &+= 1
        switch snapshot.target {
        case .selection:
            proxy.insertText(replacement)
        case .currentSentence(let charactersAfterCursor),
             .allText(let charactersAfterCursor):
            if case .allText = snapshot.target, let selected = snapshot.selectedText {
                // Reinsert the selection unchanged to collapse it at its end;
                // replacement can then use the same bounded suffix algorithm
                // as a cursor-only field.
                proxy.insertText(selected)
            }
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
            documentIdentifier: documentIdentifier,
            contextBeforeInput: proxy.documentContextBeforeInput,
            selectedText: proxy.selectedText,
            contextAfterInput: proxy.documentContextAfterInput,
            originalText: snapshot.candidate.capturedText,
            replacementText: replacement
        )
    }

    func canUndoCorrection(_ correction: AppliedCorrection) -> Bool {
        let proxy = textDocumentProxy
        guard let documentIdentifier = currentDocumentIdentifier else { return false }
        return documentIdentifier == correction.documentIdentifier
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
