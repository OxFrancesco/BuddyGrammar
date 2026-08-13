import BuddyGrammarKit
import Foundation
import Observation
import UIKit

enum KeyboardLayoutMode: Equatable {
    case letters
    case numbers
    case symbols
    case latex
    case emoji
    case handwriting
}

enum KeyboardShiftState: Equatable {
    case lowercase
    case uppercase
    case capsLock

    var isShifted: Bool { self != .lowercase }
}

enum KeyboardStatus: Equatable {
    case ready
    case correcting
    case corrected
    case correctionUndone
    case automaticCorrectionReverted(String)
    case correctionProposalReady
    case correctionProposalDismissed
    case swipeAbstained(SwipeAbstentionReason?)
    case addedToDictionary(String)
    case correctionSuggestionSuppressed
    case transcriptInserted
    case appleDictationGuidance
    case settingsGuidance
    case fullAccessRequired
    case cloudConsentRequired
    case noText
    case noPendingTranscript
    case staleContext
    case capabilityDenied(EditorCapabilityDenialReason)
    case error(String)

    var message: String {
        switch self {
        case .ready:
            "Buddy writing tools are ready."
        case .correcting:
            "Correcting…"
        case .corrected:
            "Correction applied."
        case .correctionUndone:
            "Correction undone."
        case .automaticCorrectionReverted(let original):
            "Restored \(original)."
        case .correctionProposalReady:
            "Review the Buddy change before applying it."
        case .correctionProposalDismissed:
            "Buddy change dismissed."
        case .swipeAbstained:
            "Swipe was uncertain, so nothing was inserted."
        case .addedToDictionary(let word):
            "Added \(word) to your dictionary."
        case .correctionSuggestionSuppressed:
            "That exact correction will not be suggested again."
        case .transcriptInserted:
            "Saved transcript inserted."
        case .appleDictationGuidance:
            "Tap the system mic below to start Apple Dictation."
        case .settingsGuidance:
            "Open BuddyGrammar from the Home Screen to change keyboard settings."
        case .fullAccessRequired:
            "Typing works. Enable Full Access for Buddy actions."
        case .cloudConsentRequired:
            "Accept cloud processing in BuddyGrammar to use Buddy writing tools."
        case .noText:
            "Type some text first."
        case .noPendingTranscript:
            "No saved transcript is waiting. Create one in BuddyGrammar first."
        case .staleContext:
            "The text changed, so the correction was not applied."
        case .capabilityDenied(let reason):
            reason.keyboardMessage
        case .error(let message):
            message
        }
    }

    var isError: Bool {
        switch self {
        case .fullAccessRequired, .cloudConsentRequired,
             .noText, .noPendingTranscript, .staleContext,
             .capabilityDenied, .error:
            true
        case .ready, .correcting, .corrected, .correctionUndone,
             .automaticCorrectionReverted, .transcriptInserted,
             .correctionProposalReady, .correctionProposalDismissed,
             .swipeAbstained, .addedToDictionary,
             .correctionSuggestionSuppressed,
             .appleDictationGuidance, .settingsGuidance:
            false
        }
    }
}

enum DocumentCorrectionTarget: Equatable, Sendable {
    case selection
    case currentSentence(charactersAfterCursor: Int)
    case allText(charactersAfterCursor: Int)
}

enum DocumentCorrectionRequestScope: Equatable, Sendable {
    case currentText
    case allText
}

struct DocumentCorrectionSnapshot: Equatable, Sendable {
    let documentIdentifier: UUID
    let generation: UInt64
    let contextBeforeInput: String?
    let selectedText: String?
    let contextAfterInput: String?
    let target: DocumentCorrectionTarget
    let candidate: TextCorrectionCandidate
}

struct AppliedCorrection: Equatable, Sendable {
    let documentIdentifier: UUID
    let contextBeforeInput: String?
    let selectedText: String?
    let contextAfterInput: String?
    let originalText: String
    let replacementText: String
}

struct KeyboardSuggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        case correction
        case completion
        case emoji
        case prediction
    }

    let id: String
    let kind: Kind
    let display: String
    let deleteCount: Int
    let insertion: String
    let originalText: String?
    let automaticReplacement: AutomaticSuggestionReplacement?
    let mutationReceipt: KeyboardSuggestionMutationReceipt

    var capturedFieldEpoch: Int? { mutationReceipt.fieldEpoch }
    var capturedFieldIdentifier: String? { mutationReceipt.fieldIdentifier }
    var capturedLanguageCode: String? { mutationReceipt.languageCode }

    init(
        id: String,
        kind: Kind,
        display: String,
        deleteCount: Int,
        insertion: String,
        originalText: String? = nil,
        automaticReplacement: AutomaticSuggestionReplacement? = nil,
        mutationReceipt: KeyboardSuggestionMutationReceipt
    ) {
        self.id = id
        self.kind = kind
        self.display = display
        self.deleteCount = deleteCount
        self.insertion = insertion
        self.originalText = originalText
        self.automaticReplacement = automaticReplacement
        self.mutationReceipt = mutationReceipt
    }
}

enum KeyboardCorrectionScope: Equatable {
    case selection
    case currentSentence
    case allText

    var label: String {
        switch self {
        case .selection: "Selection"
        case .currentSentence: "Current sentence"
        case .allText: "All text"
        }
    }
}

@MainActor
protocol KeyboardModelDelegate: AnyObject {
    var keyboardHasFullAccess: Bool { get }
    var contextBeforeInput: String? { get }
    var contextAfterInput: String? { get }
    var keyboardLanguage: String { get }
    var editorReturnIntent: String? { get }
    var editorFieldIdentifier: String { get }
    var editorFieldTraits: EditorFieldTraits { get }

    func insertText(_ text: String)
    func deleteBackward()
    func moveCursor(byUTF16Offset offset: Int)
    func playInputClick()
    func captureCorrectionSnapshot(
        requestScope: DocumentCorrectionRequestScope
    ) -> DocumentCorrectionSnapshot?
    func applyCorrection(
        _ replacement: String,
        to snapshot: DocumentCorrectionSnapshot
    ) -> AppliedCorrection?
    func canUndoCorrection(_ correction: AppliedCorrection) -> Bool
    func undoCorrection(_ correction: AppliedCorrection) -> Bool
}

@MainActor
private final class KeyboardInputCorrectionEditorAdapter: CorrectionCompositionEditor {
    private weak var delegate: (any KeyboardModelDelegate)?
    private let contextAccess: EditorFeatureAccess
    private let expectedContextBeforeReplacement: String?

    init(
        delegate: any KeyboardModelDelegate,
        contextAccess: EditorFeatureAccess,
        expectedContextBeforeReplacement: String? = nil
    ) {
        self.delegate = delegate
        self.contextAccess = contextAccess
        self.expectedContextBeforeReplacement = expectedContextBeforeReplacement
    }

    var correctionCompositionText: String {
        EditorContextAccessGate.read(capability: contextAccess) {
            delegate?.contextBeforeInput
        } ?? ""
    }

    func replaceCorrectionCompositionSuffix(
        _ expectedSuffix: String,
        with replacement: String
    ) -> Bool {
        guard let delegate,
              let observedContext = EditorContextAccessGate.read(
                  capability: contextAccess,
                  from: {
                  delegate.contextBeforeInput
                  }
              ),
              observedContext.hasSuffix(expectedSuffix),
              expectedContextBeforeReplacement == nil
                  || observedContext == expectedContextBeforeReplacement else {
            return false
        }
        for _ in expectedSuffix { delegate.deleteBackward() }
        delegate.insertText(replacement)
        return true
    }

    func deleteCorrectionCompositionBackward() -> Bool {
        guard let delegate else { return false }
        delegate.deleteBackward()
        return true
    }
}

@MainActor
private final class AppliedCorrectionEditorAdapter: CorrectionCompositionEditor {
    private weak var delegate: (any KeyboardModelDelegate)?
    private let correction: AppliedCorrection
    private let contextAccess: EditorFeatureAccess

    init(
        delegate: any KeyboardModelDelegate,
        correction: AppliedCorrection,
        contextAccess: EditorFeatureAccess
    ) {
        self.delegate = delegate
        self.correction = correction
        self.contextAccess = contextAccess
    }

    var correctionCompositionText: String {
        guard contextAccess.isAllowed,
              delegate?.canUndoCorrection(correction) == true else { return "" }
        return correction.replacementText
    }

    func replaceCorrectionCompositionSuffix(
        _ expectedSuffix: String,
        with replacement: String
    ) -> Bool {
        guard contextAccess.isAllowed,
              expectedSuffix == correction.replacementText,
              replacement == correction.originalText else { return false }
        return delegate?.undoCorrection(correction) ?? false
    }

    func deleteCorrectionCompositionBackward() -> Bool { false }
}

@MainActor
struct WordCompletionSource {
    private let checker = UITextChecker()

    func completions(
        for partial: String,
        language: String = "en_US",
        supplementalReplacements: [String: String]
    ) -> [String] {
        let range = NSRange(location: 0, length: (partial as NSString).length)
        var candidates = supplementalReplacements
            .filter { input, replacement in
                input.hasPrefix(partial.lowercased())
                    || replacement.lowercased().hasPrefix(partial.lowercased())
            }
            .map(\.value)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if let completions = checker.completions(
            forPartialWordRange: range,
            in: partial,
            language: language
        ) {
            candidates.append(contentsOf: completions)
        }
        return candidates
    }

    func spellingCandidates(
        for word: String,
        language: String
    ) -> [String] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelledRange = checker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: language
        )
        if misspelledRange.location != NSNotFound,
           misspelledRange.length == range.length {
            return checker.guesses(
                forWordRange: range,
                in: word,
                language: language
            ) ?? []
        }
        return []
    }

    /// Supplementary lexicon entries are exact user shortcuts, not fuzzy
    /// spelling guesses. Keeping that provenance lets the intelligence layer
    /// apply them directly at a word boundary without edit-distance filtering.
    func shortcutReplacement(
        for word: String,
        supplementalReplacements: [String: String]
    ) -> String? {
        guard let replacement = supplementalReplacements[word.lowercased()],
              !replacement.isEmpty,
              replacement.caseInsensitiveCompare(word) != .orderedSame else {
            return nil
        }
        return replacement
    }
}

private struct DeferredCorrectionLearning {
    let text: String
    let precedingContext: String?
    let languageCode: String?
    let resultingContext: String?
}

private struct LocalAutomaticCorrection {
    let originalText: String
    let replacementText: String
    let precedingContext: String
    let languageCode: String?
    let source: AutomaticCorrectionSource
}

private struct PendingCorrectionProposal {
    let proposal: ReviewableCorrectionProposal
    let snapshot: DocumentCorrectionSnapshot
    let scope: KeyboardCorrectionScope
    let languageCode: String?
    let undoDuration: TimeInterval
}

@MainActor
@Observable
final class KeyboardModel {
    private static let selectedLanguageDefaultsKey =
        "BuddyGrammarKeyboard.selectedLanguage.v1"

    var layoutMode: KeyboardLayoutMode = .letters
    var shiftState: KeyboardShiftState = .uppercase
    private(set) var status: KeyboardStatus = .fullAccessRequired
    private(set) var isStatusPresented = true
    private(set) var hasFullAccess = false
    private(set) var suggestions: [KeyboardSuggestion] = []
    private(set) var canUndoCorrection = false
    private(set) var hasPendingTranscript = false
    private(set) var automaticCorrectionOriginalText: String?
    private(set) var correctionProposal: ReviewableCorrectionProposal?
    private(set) var correctionProposalScope: KeyboardCorrectionScope?
    private(set) var keyboardPresentation: KeyboardCatalog.Presentation?
    private(set) var keyboardReturnLabel = "return"
    private(set) var keyboardAutoCapitalization: EditorAutoCapitalizationMode = .sentences
    private(set) var selectedKeyboardLanguageIdentifier: String?
    private(set) var editorFieldEpoch = 0
    private(set) var keyboardInteractionConfiguration = KeyboardInteractionRouter.Configuration()
    private(set) var editorCapabilities = EditorCapabilityPolicy.evaluate(
        traits: EditorFieldTraits(kind: .unknown),
        environment: EditorCapabilityEnvironment(
            cloudTransportAvailable: false,
            hasCloudProcessingConsent: false,
            platformVoiceAvailable: false,
            editorCanMoveCursor: true,
            sharedContainerAvailable: false
        )
    )

    @ObservationIgnored private weak var delegate: KeyboardModelDelegate?
    @ObservationIgnored private let correctionClient: OpenRouterCorrectionClient
    @ObservationIgnored private let handwritingClient: HandwritingRecognitionClient
    @ObservationIgnored private let preferences: SharedPreferences?
    @ObservationIgnored private let adaptiveStore: AdaptiveLearningStore?
    @ObservationIgnored private let keyboardCatalog: KeyboardCatalog?
    @ObservationIgnored private let languageDefaults: UserDefaults
    @ObservationIgnored private lazy var completionSource = WordCompletionSource()
    @ObservationIgnored private var correctionTask: Task<Void, Never>?
    @ObservationIgnored private var typingRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var correctionRequestID: UUID?
    @ObservationIgnored private var statusDismissTask: Task<Void, Never>?
    @ObservationIgnored private var undoDismissTask: Task<Void, Never>?
    @ObservationIgnored private var baselineStatus: KeyboardStatus = .fullAccessRequired
    @ObservationIgnored private var pendingCorrectionUndo: AppliedCorrection?
    @ObservationIgnored private var deferredCorrectionLearning: DeferredCorrectionLearning?
    @ObservationIgnored private var correctionCompositionSession =
        CorrectionCompositionSession()
    @ObservationIgnored private var automaticCorrectionExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var pendingCorrectionProposal: PendingCorrectionProposal?
    @ObservationIgnored private var supplementalReplacements: [String: String] = [:]
    @ObservationIgnored private var cachedSwipeEngine: SwipeTypingEngine?
    @ObservationIgnored private var didWarmUpConnection = false
    @ObservationIgnored private var textIntelligenceBacking: TextIntelligence?
    @ObservationIgnored private var observedTextSuffix = ObservedTextSuffix()
    @ObservationIgnored private var typingIntelligence: TypingIntelligence
    @ObservationIgnored private lazy var tapWordDecoder = TapWordDecoder()
    @ObservationIgnored private var currentWordTaps: [TapWordLatticeTap] = []
    @ObservationIgnored private var currentWordTapTargetStartedAtProvenBoundary = false
    @ObservationIgnored private var activePracticeSession: ActivePracticeSession?
    @ObservationIgnored private var lastTypingDecision: TypingDecision?
    @ObservationIgnored private var pendingRejectedDecision: TypingDecision?
    @ObservationIgnored private var adaptiveProfileIsDirty = false
    @ObservationIgnored private var observationsSinceAdaptiveSave = 0
    @ObservationIgnored private var userEnabledCapsLock = false
    @ObservationIgnored private var observedLanguageResetGeneration: UInt64?
    @ObservationIgnored private var observedTypingResetGeneration: UInt64?
    @ObservationIgnored private var languagePersonalizationWasAvailable: Bool?
    @ObservationIgnored private var typingPersonalizationWasAvailable: Bool?
    @ObservationIgnored private var cachedSettings = BuddyGrammarSettings.default
    @ObservationIgnored private var shouldPresentStaleContextAfterRefresh = false
    @ObservationIgnored private var needsDocumentContextRefresh = false

    init(
        correctionClient: OpenRouterCorrectionClient = OpenRouterCorrectionClient(),
        handwritingClient: HandwritingRecognitionClient = HandwritingRecognitionClient(),
        preferences: SharedPreferences? = SharedPreferences(),
        adaptiveStore: AdaptiveLearningStore? = AdaptiveLearningStore(),
        textIntelligence: TextIntelligence? = nil,
        languageDefaults: UserDefaults = .standard
    ) {
        self.correctionClient = correctionClient
        self.handwritingClient = handwritingClient
        self.preferences = preferences
        self.adaptiveStore = adaptiveStore
        self.languageDefaults = languageDefaults
        self.cachedSettings = preferences?.loadSettings() ?? .default
        let keyboardCatalog = try? KeyboardCatalog.bundled()
        self.keyboardCatalog = keyboardCatalog
        if let storedLanguage = languageDefaults.string(
            forKey: Self.selectedLanguageDefaultsKey
        ), keyboardCatalog?.languages.contains(where: { $0.id == storedLanguage }) == true {
            self.selectedKeyboardLanguageIdentifier = storedLanguage
        }
        if let gestures = keyboardCatalog?.gestures {
            let deleteRepeatInterval =
                TimeInterval(gestures.deleteRepeat.intervalMilliseconds) / 1_000
            self.keyboardInteractionConfiguration = KeyboardInteractionRouter.Configuration(
                cursorActivationDelay: TimeInterval(gestures.spaceCursor.activationMilliseconds) / 1_000,
                cursorStep: Double(gestures.spaceCursor.pointsPerGrapheme),
                deleteRepeatDelay: TimeInterval(gestures.deleteRepeat.initialDelayMilliseconds) / 1_000,
                deleteRepeatInterval: deleteRepeatInterval,
                minimumDeleteRepeatInterval: deleteRepeatInterval
            )
        }
        self.textIntelligenceBacking = textIntelligence
        self.typingIntelligence = TypingIntelligence(
            profile: adaptiveStore?.loadTypingProfile() ?? TypingProfile(),
            policy: .literal
        )
    }

    private var textIntelligence: TextIntelligence {
        if let textIntelligenceBacking { return textIntelligenceBacking }
        let intelligence = TextIntelligence(
            personalLanguageModel: preferences?.makePersonalLanguageModel()
                ?? PersonalLanguageModel(defaults: nil)
        )
        if !languagePersonalizationIsAvailable {
            intelligence.discardInMemoryPersonalization()
        }
        textIntelligenceBacking = intelligence
        return intelligence
    }

    func connect(delegate: KeyboardModelDelegate) {
        self.delegate = delegate
        editorFieldEpoch &+= 1
        currentWordTaps.removeAll(keepingCapacity: true)
        currentWordTapTargetStartedAtProvenBoundary = false
        correctionCompositionSession.synchronizeField(
            identifier: delegate.editorFieldIdentifier
        )
        activate()
    }

    func activate() {
        refreshAvailability()
        refreshAdaptiveState()
        refreshPendingTranscriptAvailability()
        scheduleSuggestionsRefresh()
        warmUpCorrectionConnectionIfNeeded()
    }

    private func warmUpCorrectionConnectionIfNeeded() {
        guard editorCapabilities.cloudCorrection.isAllowed,
              !didWarmUpConnection else { return }
        didWarmUpConnection = true
        Task { [correctionClient] in
            await correctionClient.warmUpConnection()
        }
    }

    func refreshAvailability() {
        refreshEditorCapabilities()

        guard editorCapabilities.cloudCorrection.isAllowed else {
            cancelCorrection()
            clearCorrectionProposal()
            clearCorrectionUndo(acceptLearning: false)
            baselineStatus = availabilityStatus()
            present(baselineStatus)
            return
        }

        let shouldPreserveCorrectionStatus = correctionTask != nil
        baselineStatus = availabilityStatus()
        if !shouldPreserveCorrectionStatus {
            present(baselineStatus)
        }
    }

    private func refreshEditorCapabilities() {
        hasFullAccess = delegate?.keyboardHasFullAccess ?? false
        let settings = preferences?.loadSettings() ?? .default
        cachedSettings = settings
        let traits = delegate?.editorFieldTraits ?? EditorFieldTraits(kind: .unknown)
        editorCapabilities = EditorCapabilityPolicy.evaluate(
            traits: traits,
            environment: EditorCapabilityEnvironment(
                cloudTransportAvailable: hasFullAccess,
                hasCloudProcessingConsent: settings.hasAcceptedCloudProcessing,
                // Third-party extensions cannot start Apple-owned Dictation.
                platformVoiceAvailable: false,
                editorCanMoveCursor: true,
                sharedContainerAvailable: hasFullAccess && preferences != nil,
                editorCanReadContext: true,
                // This extension uses explicit suffix replacement, not native
                // composing spans, so it reports that primitive conservatively.
                editorCanUseComposition: false
            )
        )
        synchronizeLearningResetState()
        refreshKeyboardPresentation(for: traits)
        configureTypingPolicy()
    }

    private func refreshKeyboardPresentation(for traits: EditorFieldTraits) {
        guard let keyboardCatalog else { return }
        let presentation = keyboardCatalog.presentation(
            for: editorCapabilities.presentationFieldKind.catalogFieldKind,
            localeIdentifier: activeKeyboardLanguageCode
        )
        let changed = keyboardPresentation != presentation
        keyboardPresentation = presentation
        keyboardAutoCapitalization = presentation.resolvedAutoCapitalization(
            hostMode: traits.autoCapitalization
        )
        keyboardReturnLabel = presentation.returnLabel(
            overridingIntent: delegate?.editorReturnIntent
        )
        if changed {
            userEnabledCapsLock = false
            if [.letters, .numbers, .symbols].contains(layoutMode) {
                layoutMode = presentation.usesNumericFieldLayout ? .numbers : .letters
            }
            refreshAutomaticShiftState()
        }
        enforceToolLayoutCapabilities()
    }

    var keyboardLetterRows: [[String]] {
        if let rows = keyboardPresentation?.layout.letterRows {
            return rows
        }
        return [
            "qwertyuiop".map { String($0) },
            "asdfghjkl".map { String($0) },
            "zxcvbnm".map { String($0) },
        ]
    }

    var keyboardNumberRows: [[String]] {
        keyboardPresentation?.layout.numberRows ?? []
    }

    var keyboardSymbolRows: [[String]] {
        keyboardPresentation?.layout.symbolRows ?? []
    }

    var keyboardNumericRows: [[String]] {
        keyboardPresentation?.numericKeyRows
            ?? [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["0"]]
    }

    var keyboardInlineKeys: [KeyboardCatalog.InlineKey] {
        keyboardPresentation?.contextualInlineKeys ?? []
    }

    var keyboardSpaceLabel: String {
        keyboardPresentation?.profile.spaceLabel ?? "space"
    }

    var keyboardLanguageButtonLabel: String {
        (keyboardPresentation?.language.id
            ?? LanguageSupport.primaryCode(for: activeKeyboardLanguageCode))
            .uppercased()
    }

    var keyboardLanguageAccessibilityLabel: String {
        guard let keyboardCatalog else { return "Change keyboard language" }
        let current = keyboardPresentation?.language
            ?? keyboardCatalog.language(for: activeKeyboardLanguageCode)
        let next = keyboardCatalog.nextLanguage(after: current.id)
        return keyboardCatalog.languageSwitchAccessibilityLabel(
            from: current,
            to: next,
            displayLocaleIdentifier: Locale.preferredLanguages.first
        )
    }

    func toggleKeyboardLanguage() {
        guard let keyboardCatalog else { return }
        let current = keyboardPresentation?.language
            ?? keyboardCatalog.language(for: activeKeyboardLanguageCode)
        let next = keyboardCatalog.nextLanguage(after: current.id)
        selectedKeyboardLanguageIdentifier = next.id
        languageDefaults.set(next.id, forKey: Self.selectedLanguageDefaultsKey)
        cancelCorrection()
        clearCorrectionProposal()
        currentWordTaps.removeAll(keepingCapacity: true)
        observedTextSuffix.clear()
        cachedSwipeEngine = nil
        refreshKeyboardPresentation(
            for: delegate?.editorFieldTraits ?? EditorFieldTraits(kind: .unknown)
        )
        configureTypingPolicy()
        refreshSuggestions()
    }

    private var activeKeyboardLanguageCode: String {
        selectedKeyboardLanguageIdentifier
            ?? delegate?.keyboardLanguage
            ?? Locale.preferredLanguages.first
            ?? LanguageSupport.defaultPrimaryCode
    }

    var handwritingLanguageCode: String { activeKeyboardLanguageCode }

    var usesNumericFieldLayout: Bool {
        keyboardPresentation?.usesNumericFieldLayout == true
    }

    func alternates(for key: String) -> [String] {
        keyboardPresentation?.language.alternates[key.lowercased()] ?? []
    }

    @discardableResult
    private func requireCapability(_ access: EditorFeatureAccess) -> Bool {
        guard case .denied(let reason) = access else { return true }
        present(.capabilityDenied(reason))
        return false
    }

    private func intelligenceContextBeforeInput() -> String? {
        EditorContextAccessGate.read(capability: editorCapabilities.readContext) {
            delegate?.contextBeforeInput
        }
    }

    private func intelligenceContextAfterInput() -> String? {
        EditorContextAccessGate.read(capability: editorCapabilities.readContext) {
            delegate?.contextAfterInput
        }
    }

    private func enforceToolLayoutCapabilities() {
        let access: EditorFeatureAccess? = switch layoutMode {
        case .handwriting: editorCapabilities.localHandwriting
        case .latex: editorCapabilities.literalTools
        case .emoji: editorCapabilities.directLocalInsertion
        case .letters, .numbers, .symbols: nil
        }
        guard access?.isAllowed == false else { return }
        layoutMode = keyboardPresentation?.usesNumericFieldLayout == true ? .numbers : .letters
    }

    func insertCharacter(_ character: String) {
        lastTypingDecision = nil
        pendingRejectedDecision = nil
        cancelCorrectionForLocalEdit()
        var automaticCorrection: LocalAutomaticCorrection?
        if Self.autocorrectionBoundaryCharacters.contains(character) {
            automaticCorrection = commitCurrentWord()
            currentWordTaps.removeAll(keepingCapacity: true)
        } else {
            observedTextSuffix.clear()
            if !character.allSatisfy({ $0.isLetter || $0 == "'" }) {
                currentWordTaps.removeAll(keepingCapacity: true)
            }
        }
        let output = shiftState.isShifted && layoutMode == .letters
            ? character.uppercased()
            : character
        if Self.autocorrectionBoundaryCharacters.contains(character),
           editorCapabilities.readContext.isAllowed {
            let whitespaceToDelete = RecognizedTextFormatter.whitespaceToDeleteBefore(
                output,
                contextBeforeInput: intelligenceContextBeforeInput()
            )
            for _ in 0..<whitespaceToDelete {
                delegate?.deleteBackward()
            }
        }
        delegate?.insertText(output)
        if let automaticCorrection {
            beginAutomaticCorrectionReceipt(
                automaticCorrection,
                boundary: output
            )
        }

        refreshAfterEditorMutation(ownedInsertion: output)
    }

    /// Resolves a physical touch without changing the visible keyboard. The
    /// coordinate is already normalized into QWERTY key-space by the view.
    func insertLetter(
        at keySpacePoint: CGPoint,
        literalKey: Character,
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard editorCapabilities.suggestions.isAllowed,
              editorCapabilities.readContext.isAllowed else {
            insertLiteralCharacter(String(literalKey))
            return
        }
        guard let context = intelligenceContextBeforeInput() else {
            insertLiteralCharacter(String(literalKey))
            return
        }
        let normalizedLiteral = Character(String(literalKey).lowercased())
        let tap = TouchSample(
            x: keySpacePoint.x,
            y: keySpacePoint.y,
            literalKey: normalizedLiteral,
            timestamp: timestamp
        )

        if activePracticeSession == nil,
           let pendingRejectedDecision,
           timestamp - pendingRejectedDecision.receipt.tap.timestamp <= 3 {
            typingIntelligence.observe(
                .rejection(
                    receipt: pendingRejectedDecision.receipt,
                    correctedKey: normalizedLiteral,
                    source: .retype
                )
            )
            markAdaptiveProfileDirty()
        }
        pendingRejectedDecision = nil

        let decision = typingIntelligence.resolve(
            tap: tap,
            context: TypingContext(
                rawText: context,
                languageCode: activeKeyboardLanguageCode
            )
        )

        if let intendedKey = expectedPracticeKey(atResponseLength: context.count) {
            typingIntelligence.observe(
                .positive(
                    receipt: decision.receipt,
                    intendedKey: intendedKey,
                    source: .practice
                )
            )
            markAdaptiveProfileDirty()
        }

        recordCurrentWordTap(
            TapWordLatticeTap(decision: decision),
            startsAtProvenBoundary: TypingContextAnalyzer.rawTrailingWord(in: context) == nil
        )
        insertCharacter(String(decision.key))
        lastTypingDecision = decision
    }

    /// Accessibility activation is intentionally literal: VoiceOver users
    /// selected a named key rather than an ambiguous point between keys.
    func insertLiteralCharacter(_ character: String) {
        lastTypingDecision = nil
        pendingRejectedDecision = nil
        if editorCapabilities.suggestions.isAllowed,
           editorCapabilities.readContext.isAllowed,
           let context = intelligenceContextBeforeInput(),
           let key = character.first,
           character.count == 1,
           key.isLetter {
            recordCurrentWordTap(
                TapWordLatticeTap(
                    literalKey: key,
                    resolvedKey: key,
                    candidates: [TypingCandidate(key: key, confidence: 1)]
                ),
                startsAtProvenBoundary: TypingContextAnalyzer
                    .rawTrailingWord(in: context) == nil
            )
        }
        insertCharacter(character)
    }

    func insertSpace() {
        lastTypingDecision = nil
        pendingRejectedDecision = nil
        cancelCorrectionForLocalEdit()
        let automaticCorrection = commitCurrentWord()
        currentWordTaps.removeAll(keepingCapacity: true)
        delegate?.insertText(" ")
        if let automaticCorrection {
            beginAutomaticCorrectionReceipt(automaticCorrection, boundary: " ")
        }
        refreshAfterEditorMutation(ownedInsertion: " ")
    }

    func insertReturn() {
        lastTypingDecision = nil
        pendingRejectedDecision = nil
        cancelCorrectionForLocalEdit()
        let automaticCorrection = commitCurrentWord()
        currentWordTaps.removeAll(keepingCapacity: true)
        delegate?.insertText("\n")
        if let automaticCorrection {
            beginAutomaticCorrectionReceipt(automaticCorrection, boundary: "\n")
        }
        refreshAfterEditorMutation(ownedInsertion: "\n")
    }

    func deleteBackward() {
        if correctionCompositionSession.snapshot.receiptMode == .automatic {
            cancelCorrection()
            clearCorrectionUndo(acceptLearning: false)
            if revertAutomaticCorrectionIfPossible(mode: .immediateBackspace) {
                lastTypingDecision = nil
                pendingRejectedDecision = nil
                currentWordTaps.removeAll(keepingCapacity: true)
                observedTextSuffix.clear()
                refreshAfterEditorMutation()
                return
            }
        }
        if let decision = lastTypingDecision,
           ProcessInfo.processInfo.systemUptime - decision.receipt.tap.timestamp <= 3 {
            pendingRejectedDecision = decision
        }
        lastTypingDecision = nil
        cancelCorrectionForLocalEdit()
        observedTextSuffix.clear()
        if !currentWordTaps.isEmpty {
            currentWordTaps.removeLast()
        }
        delegate?.deleteBackward()
        refreshAfterEditorMutation()
    }

    func deleteWordBackward() {
        guard let delegate else { return }
        cancelCorrectionForLocalEdit()
        lastTypingDecision = nil
        pendingRejectedDecision = nil
        currentWordTaps.removeAll(keepingCapacity: true)
        observedTextSuffix.clear()
        guard editorCapabilities.readContext.isAllowed else {
            delegate.deleteBackward()
            refreshAfterEditorMutation()
            return
        }
        guard let contextBeforeInput = intelligenceContextBeforeInput() else {
            // A host may temporarily withhold its context even though text is
            // present. Keep the visible action useful without guessing across
            // an editor boundary.
            delegate.deleteBackward()
            refreshAfterEditorMutation()
            return
        }
        let deletionCount = KeyboardDeletionPolicy.deletionCount(
            contextBeforeInput: contextBeforeInput,
            // UITextDocumentProxy exposes a bounded prefix, not a completeness
            // guarantee. A run that reaches its leading edge may therefore be
            // only the tail of a longer word or whitespace run.
            leadingEdgeMayBeTruncated: true
        )
        guard deletionCount > 0 else { return }
        for _ in 0..<deletionCount {
            delegate.deleteBackward()
        }
        refreshAfterEditorMutation()
    }

    func moveCursor(byCharacterOffset offset: Int) {
        guard offset != 0 else { return }
        refreshEditorCapabilities()
        guard requireCapability(editorCapabilities.cursorMovement) else { return }
        cancelCorrectionForLocalEdit()
        lastTypingDecision = nil
        pendingRejectedDecision = nil
        currentWordTaps.removeAll(keepingCapacity: true)
        observedTextSuffix.clear()
        let editorOffset = if editorCapabilities.readContext.isAllowed {
            KeyboardCursorOffsetPolicy.utf16Offset(
                forGraphemeDelta: offset,
                contextBeforeInput: intelligenceContextBeforeInput(),
                contextAfterInput: intelligenceContextAfterInput()
            )
        } else {
            // Context-denied fields must remain literal and private. Retain the
            // platform's one-unit fallback without reading surrounding text.
            offset
        }
        guard editorOffset != 0 else { return }
        delegate?.moveCursor(byUTF16Offset: editorOffset)
        refreshSuggestions()
    }

    /// Public extension-owned feedback seam. Local-input surfaces such as the
    /// emoji search keyboard can request the same system-respecting click even
    /// when they do not insert through the host text proxy.
    func playInputClick() {
        delegate?.playInputClick()
    }

    func toggleShift() {
        userEnabledCapsLock = false
        shiftState = shiftState == .lowercase ? .uppercase : .lowercase
    }

    func activateCapsLock() {
        userEnabledCapsLock = true
        shiftState = .capsLock
    }

    func setLayout(_ mode: KeyboardLayoutMode) {
        refreshEditorCapabilities()
        let requestedCapability: EditorFeatureAccess? = switch mode {
        case .handwriting: editorCapabilities.localHandwriting
        case .latex: editorCapabilities.literalTools
        case .emoji: editorCapabilities.directLocalInsertion
        case .letters, .numbers, .symbols: nil
        }
        if let requestedCapability,
           !requireCapability(requestedCapability) {
            enforceToolLayoutCapabilities()
            return
        }
        cancelCorrectionForLocalEdit()
        currentWordTaps.removeAll(keepingCapacity: true)
        let isReturningFromTool = [.latex, .emoji, .handwriting].contains(layoutMode)
        layoutMode = mode == .letters && isReturningFromTool && usesNumericFieldLayout
            ? .numbers
            : mode
        refreshAfterEditorMutation()
    }

    func returnToPrimaryLayout() {
        setLayout(usesNumericFieldLayout ? .numbers : .letters)
    }

    func toggleLayout() {
        setLayout(layoutMode == .letters ? .numbers : .letters)
    }

    func toggleSymbolPlane() {
        setLayout(layoutMode == .symbols ? .numbers : .symbols)
    }

    func insertSuggestion(_ suggestion: KeyboardSuggestion) {
        refreshEditorCapabilities()
        guard editorCapabilities.suggestions.isAllowed,
              editorCapabilities.readContext.isAllowed,
              let delegate,
              let context = intelligenceContextBeforeInput() else {
            suggestions = []
            return
        }
        guard suggestion.deleteCount == suggestion.mutationReceipt.deleteCount,
              suggestion.mutationReceipt.matches(
                  fieldEpoch: editorFieldEpoch,
                  fieldIdentifier: delegate.editorFieldIdentifier,
                  languageCode: activeKeyboardLanguageCode,
                  contextBeforeInput: context
              ) else {
            present(.staleContext)
            refreshSuggestions()
            return
        }
        guard suggestion.kind != .correction
                || suggestion.automaticReplacement != nil else {
            present(.staleContext)
            refreshSuggestions()
            return
        }
        if let replacement = suggestion.automaticReplacement {
            guard replacement.matches(
                      contextBeforeInput: context,
                      deleteCount: suggestion.deleteCount,
                      insertion: suggestion.insertion
                  ) else {
                present(.staleContext)
                refreshSuggestions()
                return
            }
        }
        if let replacement = suggestion.automaticReplacement {
            cancelCorrectionForLocalEdit()
            observedTextSuffix.clear()
            currentWordTaps.removeAll(keepingCapacity: true)
            correctionCompositionSession.synchronizeField(
                identifier: delegate.editorFieldIdentifier
            )
            let correction = LocalAutomaticCorrection(
                originalText: replacement.originalText,
                replacementText: replacement.replacementText,
                precedingContext: replacement.precedingContext,
                languageCode: activeKeyboardLanguageCode,
                source: replacement.source
            )
            let now = ProcessInfo.processInfo.systemUptime * 1_000
            let effect = correctionCompositionSession.applyAutomatic(
                in: KeyboardInputCorrectionEditorAdapter(
                    delegate: delegate,
                    contextAccess: editorCapabilities.readContext,
                    expectedContextBeforeReplacement: replacement.expectedContextBeforeInput
                ),
                originalText: replacement.originalText,
                replacementText: replacement.replacementText,
                boundary: replacement.boundary,
                precedingContext: replacement.precedingContext,
                languageCode: activeKeyboardLanguageCode,
                source: replacement.source,
                atMilliseconds: now
            )
            guard effect.didMutateEditor else {
                present(.staleContext)
                refreshSuggestions()
                return
            }
            activateAutomaticCorrectionReceipt(
                correction,
                effect: effect,
                atMilliseconds: now
            )
            observedTextSuffix.observe(
                committedText: replacement.insertion,
                contextBeforeInput: replacement.precedingContext + replacement.insertion
            )
            refreshAfterEditorMutation(ownedInsertion: replacement.insertion)
            return
        }

        guard let immediateContext = intelligenceContextBeforeInput(),
              suggestion.mutationReceipt.matches(
                  fieldEpoch: editorFieldEpoch,
                  fieldIdentifier: delegate.editorFieldIdentifier,
                  languageCode: activeKeyboardLanguageCode,
                  contextBeforeInput: immediateContext
              ) else {
            present(.staleContext)
            refreshSuggestions()
            return
        }
        cancelCorrectionForLocalEdit()
        observedTextSuffix.clear()
        currentWordTaps.removeAll(keepingCapacity: true)
        guard let finalContext = intelligenceContextBeforeInput(),
              suggestion.mutationReceipt.matches(
                  fieldEpoch: editorFieldEpoch,
                  fieldIdentifier: delegate.editorFieldIdentifier,
                  languageCode: activeKeyboardLanguageCode,
                  contextBeforeInput: finalContext
              ) else {
            present(.staleContext)
            refreshSuggestions()
            return
        }
        let prefix = String(context.dropLast(suggestion.deleteCount))
        for _ in 0..<suggestion.deleteCount {
            delegate.deleteBackward()
        }
        delegate.insertText(suggestion.insertion)
        if suggestion.kind != .emoji {
            observePersonalCommittedText(
                suggestion.insertion,
                precededBy: prefix,
                languageCode: activeKeyboardLanguageCode
            )
            observedTextSuffix.observe(
                committedText: suggestion.insertion,
                contextBeforeInput: prefix + suggestion.insertion
            )
        }
        refreshAfterEditorMutation(ownedInsertion: suggestion.insertion)
    }

    func addToDictionary(from suggestion: KeyboardSuggestion) {
        refreshEditorCapabilities()
        guard requireCapability(editorCapabilities.suggestions),
              requireCapability(editorCapabilities.personalizedLearning),
              requireCapability(editorCapabilities.readContext),
              languagePersonalizationIsAvailable else {
            if !languagePersonalizationIsAvailable {
                present(.capabilityDenied(.sharedContainerUnavailable))
            }
            refreshSuggestions()
            return
        }
        guard let target = ownedCorrectionPreferenceTarget(for: suggestion) else {
            present(.staleContext)
            refreshSuggestions()
            return
        }
        _ = textIntelligence.addToDictionary(
            target.replacement.originalText,
            languageCode: target.languageCode
        )
        present(.addedToDictionary(target.replacement.originalText))
        refreshSuggestions()
    }

    func neverSuggestCorrection(_ suggestion: KeyboardSuggestion) {
        refreshEditorCapabilities()
        guard requireCapability(editorCapabilities.suggestions),
              requireCapability(editorCapabilities.personalizedLearning),
              requireCapability(editorCapabilities.readContext),
              languagePersonalizationIsAvailable else {
            if !languagePersonalizationIsAvailable {
                present(.capabilityDenied(.sharedContainerUnavailable))
            }
            refreshSuggestions()
            return
        }
        guard let target = ownedCorrectionPreferenceTarget(for: suggestion) else {
            present(.staleContext)
            refreshSuggestions()
            return
        }
        _ = textIntelligence.neverSuggestCorrection(
            typed: target.replacement.originalText,
            suggestion: target.replacement.replacementText,
            languageCode: target.languageCode
        )
        present(.correctionSuggestionSuppressed)
        refreshSuggestions()
    }

    var allowsCorrectionPreferenceActions: Bool {
        languagePersonalizationIsAvailable
            && editorCapabilities.suggestions.isAllowed
            && editorCapabilities.personalizedLearning.isAllowed
            && editorCapabilities.readContext.isAllowed
    }

    private func ownedCorrectionPreferenceTarget(
        for suggestion: KeyboardSuggestion
    ) -> (replacement: AutomaticSuggestionReplacement, languageCode: String)? {
        guard suggestion.kind == .correction,
              let replacement = suggestion.automaticReplacement,
              suggestion.originalText == replacement.originalText,
              suggestion.display == replacement.replacementText,
              suggestion.capturedFieldEpoch == editorFieldEpoch,
              let delegate,
              suggestion.capturedFieldIdentifier == delegate.editorFieldIdentifier,
              let languageCode = suggestion.capturedLanguageCode,
              languageCode == activeKeyboardLanguageCode,
              let contextBeforeInput = intelligenceContextBeforeInput(),
              suggestion.mutationReceipt.matches(
                  fieldEpoch: editorFieldEpoch,
                  fieldIdentifier: delegate.editorFieldIdentifier,
                  languageCode: languageCode,
                  contextBeforeInput: contextBeforeInput
              ),
              replacement.matches(
                  contextBeforeInput: contextBeforeInput,
                  deleteCount: suggestion.deleteCount,
                  insertion: suggestion.insertion
              ) else {
            return nil
        }
        return (replacement, languageCode)
    }

    func insertEmoji(_ emoji: String) {
        refreshEditorCapabilities()
        guard requireCapability(editorCapabilities.directLocalInsertion),
              let delegate else { return }
        cancelCorrectionForLocalEdit()
        observedTextSuffix.clear()
        currentWordTaps.removeAll(keepingCapacity: true)
        delegate.insertText(emoji)
        refreshAfterEditorMutation(ownedInsertion: emoji)
    }

    @discardableResult
    func insertRecognizedText(_ text: String, capturedFieldEpoch: Int) -> Bool {
        refreshEditorCapabilities()
        guard capturedFieldEpoch == editorFieldEpoch,
              requireCapability(editorCapabilities.localHandwriting) else {
            return false
        }
        cancelCorrectionForLocalEdit()
        let context = intelligenceContextBeforeInput()
        let formatted = HandwritingTextFormatter.textForInsertion(
            text,
            contextBeforeInput: context,
            languageCode: activeKeyboardLanguageCode
        )
        return commitRecognizedText(formatted, context: context)
    }

    @discardableResult
    private func commitRecognizedText(
        _ text: String,
        context: String?,
        languageCode: String? = nil
    ) -> Bool {
        guard let delegate else { return false }
        observedTextSuffix.clear()
        currentWordTaps.removeAll(keepingCapacity: true)
        let whitespaceToDelete = RecognizedTextFormatter.whitespaceToDeleteBefore(
            text,
            contextBeforeInput: context
        )
        for _ in 0..<whitespaceToDelete {
            delegate.deleteBackward()
        }
        let retainedContext = context.map {
            String($0.dropLast(whitespaceToDelete))
        }
        let insertion = RecognizedTextFormatter.textForInsertion(
            text,
            contextBeforeInput: retainedContext
        )
        guard !insertion.isEmpty else { return false }
        delegate.insertText(insertion)
        observePersonalCommittedText(
            insertion,
            precededBy: retainedContext,
            languageCode: languageCode ?? activeKeyboardLanguageCode
        )
        observedTextSuffix.observe(
            committedText: insertion,
            contextBeforeInput: (retainedContext ?? "") + insertion
        )
        refreshAfterEditorMutation(ownedInsertion: insertion)
        return true
    }

    func updateSupplementaryLexicon(_ lexicon: UILexicon) {
        supplementalReplacements = Dictionary(
            lexicon.entries.map { ($0.userInput.lowercased(), $0.documentText) },
            uniquingKeysWith: { first, _ in first }
        )
        cachedSwipeEngine = nil
    }

    func commitSwipe(samples: [SwipePathSample]) {
        refreshEditorCapabilities()
        guard layoutMode == .letters,
              samples.count >= 2 else {
            suggestions = []
            return
        }
        guard requireCapability(editorCapabilities.swipeTyping) else {
            suggestions = []
            return
        }
        cancelCorrection()
        clearCorrectionProposal()
        let context = intelligenceContextBeforeInput()
        let recognition = KeyboardLatencyRecorder.production.measure(.swipeDecode) {
            swipeEngine().recognize(
                samples: samples,
                limit: 3,
                previousWord: lastWord(in: context),
                languageCode: activeKeyboardLanguageCode
            )
        }
        guard let best = recognition.acceptedCandidate else {
            suggestions = []
            present(.swipeAbstained(recognition.abstentionReason))
            return
        }

        playInputClick()
        cancelCorrectionForLocalEdit()
        currentWordTaps.removeAll(keepingCapacity: true)
        let word = applyingShift(to: best.word)
        commitRecognizedText(word, context: context)
        if shiftState == .uppercase {
            shiftState = .lowercase
        }

        // Offer runner-up replacements only when the host editor allows
        // dictionary intelligence. Structured and no-suggestion fields must
        // stay free of candidates even after a direct swipe gesture.
        if activePracticeSession == nil,
           editorCapabilities.suggestions.isAllowed,
           let committedContext = intelligenceContextBeforeInput(),
           let acceptedWord = TypingContextAnalyzer.rawTrailingWord(in: committedContext),
           let receipt = suggestionMutationReceipt(
               contextBeforeInput: committedContext,
               deleteCount: acceptedWord.count,
               targetOwnership: .keyboardOwned
           ) {
            let precedingContext = String(committedContext.dropLast(acceptedWord.count))
            suggestions = recognition.candidates.dropFirst().compactMap { alternate in
                let display = applyingShift(to: alternate.word, matching: word)
                guard let replacement = AutomaticSuggestionReplacement(
                    originalText: acceptedWord,
                    replacementText: display,
                    boundary: "",
                    precedingContext: precedingContext,
                    source: .swipe
                ) else { return nil }
                return KeyboardSuggestion(
                    id: "swipe-\(alternate.word)",
                    kind: .correction,
                    display: display,
                    deleteCount: acceptedWord.count,
                    insertion: display,
                    originalText: acceptedWord,
                    automaticReplacement: replacement,
                    mutationReceipt: receipt
                )
            }
        } else {
            suggestions = []
        }
    }

    /// Compatibility for callers that cannot yet provide timing. Production
    /// pointer routing uses the timed overload above.
    func commitSwipe(path: [CGPoint]) {
        commitSwipe(
            samples: path.enumerated().map { index, point in
                SwipePathSample(
                    point: point,
                    timestampMilliseconds: Double(index * 16)
                )
            }
        )
    }

    private func lastWord(in context: String?) -> String? {
        context.flatMap { TextWordTokenizer.words(in: $0).last }
    }

    private func recordCurrentWordTap(
        _ tap: TapWordLatticeTap,
        startsAtProvenBoundary: Bool
    ) {
        guard currentWordTaps.count < TapWordDecoder.maximumTaps else { return }
        if currentWordTaps.isEmpty {
            currentWordTapTargetStartedAtProvenBoundary = startsAtProvenBoundary
        }
        currentWordTaps.append(tap)
    }

    private func swipeEngine() -> SwipeTypingEngine {
        if let cachedSwipeEngine { return cachedSwipeEngine }
        let engine = SwipeTypingEngine(
            extraWords: Array(supplementalReplacements.values)
        )
        cachedSwipeEngine = engine
        return engine
    }

    private func applyingShift(to word: String, matching reference: String? = nil) -> String {
        if let reference {
            return reference.first?.isUppercase == true ? capitalized(word) : word
        }
        switch shiftState {
        case .lowercase: return word
        case .uppercase: return capitalized(word)
        case .capsLock: return word.uppercased()
        }
    }

    private var languagePersonalizationIsAvailable: Bool {
        hasFullAccess && preferences != nil
    }

    private var typingPersonalizationIsAvailable: Bool {
        languagePersonalizationIsAvailable && adaptiveStore != nil
    }

    private func discardPendingPersonalLearningState() {
        automaticCorrectionExpiryTask?.cancel()
        automaticCorrectionExpiryTask = nil
        automaticCorrectionOriginalText = nil
        deferredCorrectionLearning = nil
        pendingCorrectionUndo = nil
        canUndoCorrection = false
        if correctionCompositionSession.snapshot.receiptMode != nil {
            correctionCompositionSession.externalEditObserved()
        }
        currentWordTaps.removeAll(keepingCapacity: true)
        observedTextSuffix.clear()
    }

    /// Reconciles both live learning families with App Group reset epochs.
    /// Losing access drops only memory; returning access or a newer epoch
    /// reloads a generation-owned durable snapshot.
    private func synchronizeLearningResetState() {
        let languageAvailable = languagePersonalizationIsAvailable
        let generations = languageAvailable
            ? preferences?.loadLearningResetGenerations()
            : nil

        if languageAvailable, let languageGeneration = generations?.language {
            let generationChanged = observedLanguageResetGeneration.map {
                $0 != languageGeneration
            } == true
            if languagePersonalizationWasAvailable == false || generationChanged {
                discardPendingPersonalLearningState()
                textIntelligence.reloadPersonalization()
            }
            observedLanguageResetGeneration = languageGeneration
        } else {
            if languagePersonalizationWasAvailable != false {
                discardPendingPersonalLearningState()
                textIntelligenceBacking?.discardInMemoryPersonalization()
            }
            observedLanguageResetGeneration = nil
        }
        languagePersonalizationWasAvailable = languageAvailable

        let typingAvailable = typingPersonalizationIsAvailable
        if typingAvailable,
           let typingGeneration = generations?.typing,
           let adaptiveStore {
            if typingPersonalizationWasAvailable == false
                || observedTypingResetGeneration.map({ $0 != typingGeneration }) == true {
                typingIntelligence = TypingIntelligence(
                    profile: adaptiveStore.loadTypingProfile(),
                    policy: .literal
                )
                adaptiveProfileIsDirty = false
                observationsSinceAdaptiveSave = 0
                lastTypingDecision = nil
                pendingRejectedDecision = nil
            }
            observedTypingResetGeneration = typingGeneration
        } else {
            if typingPersonalizationWasAvailable != false {
                typingIntelligence = TypingIntelligence(policy: .literal)
                adaptiveProfileIsDirty = false
                observationsSinceAdaptiveSave = 0
                lastTypingDecision = nil
                pendingRejectedDecision = nil
            }
            observedTypingResetGeneration = nil
        }
        typingPersonalizationWasAvailable = typingAvailable
    }

    private func refreshAdaptiveState() {
        synchronizeLearningResetState()
        activePracticeSession = typingPersonalizationIsAvailable
            ? adaptiveStore?.loadActivePracticeSession()
            : nil
        if !adaptiveProfileIsDirty {
            typingIntelligence = TypingIntelligence(
                profile: typingPersonalizationIsAvailable
                    ? adaptiveStore?.loadTypingProfile() ?? TypingProfile()
                    : TypingProfile(),
                policy: typingPolicy()
            )
        } else {
            configureTypingPolicy()
        }
    }

    private func configureTypingPolicy() {
        let policy = typingPolicy()
        guard typingIntelligence.policy != policy else { return }
        typingIntelligence = TypingIntelligence(
            profile: typingIntelligence.snapshot,
            policy: policy
        )
    }

    private func typingPolicy() -> TypingPolicy {
        guard editorCapabilities.automaticCorrection.isAllowed else {
            return .literal
        }
        if activePracticeSession != nil {
            return cachedSettings.adaptiveTypingEnabled ? .practice : .literal
        }
        guard cachedSettings.adaptiveTypingEnabled else {
            return .literal
        }
        guard typingPersonalizationIsAvailable else {
            return .generic
        }
        return editorCapabilities.personalizedLearning.isAllowed
            ? .personalizedLearning
            : .personalizedReadOnly
    }

    private func expectedPracticeKey(atResponseLength responseLength: Int) -> Character? {
        guard cachedSettings.personalizedPracticeEnabled,
              let session = activePracticeSession else {
            return nil
        }
        let target = Array(session.expectedText)
        guard target.indices.contains(responseLength) else { return nil }
        let candidate = Character(String(target[responseLength]).lowercased())
        guard candidate.isLetter else { return nil }
        return candidate
    }

    private func markAdaptiveProfileDirty() {
        guard typingPersonalizationIsAvailable else { return }
        adaptiveProfileIsDirty = true
        observationsSinceAdaptiveSave += 1
        if observationsSinceAdaptiveSave >= 8 {
            persistAdaptiveProfileIfNeeded()
        }
    }

    private func persistAdaptiveProfileIfNeeded(force: Bool = false) {
        synchronizeLearningResetState()
        guard adaptiveProfileIsDirty, force || observationsSinceAdaptiveSave >= 8 else {
            return
        }
        guard typingPersonalizationIsAvailable,
              let observedTypingResetGeneration else {
            adaptiveProfileIsDirty = false
            observationsSinceAdaptiveSave = 0
            return
        }
        do {
            let didSave = try adaptiveStore?.saveTypingProfile(
                typingIntelligence.snapshot,
                expectedResetGeneration: observedTypingResetGeneration
            ) ?? false
            guard didSave else {
                synchronizeLearningResetState()
                return
            }
            adaptiveProfileIsDirty = false
            observationsSinceAdaptiveSave = 0
        } catch {
            // Typing must never block or fail because aggregate persistence did.
        }
    }

    private var allowsPersonalLanguageLearning: Bool {
        activePracticeSession == nil
            && languagePersonalizationIsAvailable
            && editorCapabilities.personalizedLearning.isAllowed
    }

    private func observePersonalCommittedText(
        _ text: String,
        precededBy context: String?,
        languageCode: String?
    ) {
        synchronizeLearningResetState()
        guard allowsPersonalLanguageLearning else { return }
        textIntelligence.observeCommittedText(
            text,
            precededBy: context,
            languageCode: languageCode
        )
    }

    func recognizeHandwriting(_ imageData: Data) async throws -> String? {
        refreshEditorCapabilities()
        guard requireCapability(editorCapabilities.cloudHandwriting),
              let preferences else {
            return nil
        }

        let languageCode = activeKeyboardLanguageCode
            .split(separator: "-")
            .first
            .map(String.init)
        return try await handwritingClient.recognize(
            imageData: imageData,
            clientID: preferences.installationIdentifier(),
            modelID: cachedSettings.activeOpenRouterModelID,
            languageCode: languageCode
        )
    }

    func canPublishHandwritingCandidate(
        capturedFieldEpoch: Int,
        requiresCloud: Bool
    ) -> Bool {
        refreshEditorCapabilities()
        guard capturedFieldEpoch == editorFieldEpoch,
              editorCapabilities.localHandwriting.isAllowed else { return false }
        return !requiresCloud || editorCapabilities.cloudHandwriting.isAllowed
    }

    func refreshSuggestions() {
        synchronizeLearningResetState()
        updateSuggestions(context: intelligenceContextBeforeInput())
    }

    private func updateSuggestions(context: String?) {
        guard activePracticeSession == nil,
              editorCapabilities.suggestions.isAllowed,
              editorCapabilities.readContext.isAllowed,
              let context else {
            if !suggestions.isEmpty { suggestions = [] }
            return
        }
        let analysis = TypingContextAnalyzer.analyze(context)
        let emojiSuggestion = emojiSuggestion(for: analysis, context: context)
        let textLimit = emojiSuggestion == nil ? 3 : 2
        var next = localTextSuggestions(for: context, limit: textLimit).compactMap {
            keyboardSuggestion(from: $0, context: context)
        }
        if let latticeSuggestion = latticeSuggestion(for: context),
           !next.contains(where: {
               $0.display.caseInsensitiveCompare(latticeSuggestion.display) == .orderedSame
           }) {
            next.insert(latticeSuggestion, at: 0)
        }
        if let emojiSuggestion {
            next.append(emojiSuggestion)
        }
        let refreshedSuggestions = Array(next.prefix(3))
        if suggestions != refreshedSuggestions {
            suggestions = refreshedSuggestions
        }
    }

    private func latticeSuggestion(for context: String?) -> KeyboardSuggestion? {
        guard let rawVisibleWord = TypingContextAnalyzer.rawTrailingWord(in: context),
              case .typingWord(let visibleWord) = TypingContextAnalyzer
                  .analyze(context).mode,
              currentWordTaps.count == TapWordDecoder.expectedTapCount(
                  for: visibleWord
              ),
              textIntelligence.usageCount(
                  for: visibleWord,
                  languageCode: activeKeyboardLanguageCode
              ) < 3 else {
            return nil
        }
        let precedingContext = String((context ?? "").dropLast(rawVisibleWord.count))
        let result = tapWordDecoder.decode(
            currentWordTaps,
            previousWord: lastWord(in: precedingContext),
            languageCode: activeKeyboardLanguageCode,
            limit: 5
        )
        guard let best = TapWordAcceptancePolicy.suggestion.acceptedCandidate(
            from: result
        ) else {
            return nil
        }
        let candidate = matchingCapitalization(of: best.word, to: rawVisibleWord)
        guard candidate.caseInsensitiveCompare(visibleWord) != .orderedSame,
              !textIntelligence.isCorrectionSuppressed(
                  typed: visibleWord,
                  suggestion: candidate,
                  languageCode: activeKeyboardLanguageCode
              ) else {
            return nil
        }
        guard let replacement = AutomaticSuggestionReplacement(
            originalText: rawVisibleWord,
            replacementText: candidate,
            boundary: " ",
            precedingContext: precedingContext,
            source: .tapLattice
        ), let receipt = suggestionMutationReceipt(
            contextBeforeInput: context ?? "",
            deleteCount: rawVisibleWord.count
        ) else { return nil }
        return KeyboardSuggestion(
            id: "tap-lattice-\(candidate)",
            kind: .correction,
            display: candidate,
            deleteCount: rawVisibleWord.count,
            insertion: candidate + " ",
            originalText: rawVisibleWord,
            automaticReplacement: replacement,
            mutationReceipt: receipt
        )
    }

    private func localTextSuggestions(
        for context: String?,
        limit: Int
    ) -> [TextSuggestion] {
        let languageCode = activeKeyboardLanguageCode
        guard case .typingWord(let partial) = TypingContextAnalyzer.analyze(context).mode else {
            return textIntelligence.suggestions(
                for: context,
                languageCode: languageCode,
                limit: limit
            )
        }

        let checkerLanguage = languageCode.replacingOccurrences(of: "-", with: "_")
        return textIntelligence.suggestions(
            for: context,
            shortcutReplacement: completionSource.shortcutReplacement(
                for: partial,
                supplementalReplacements: supplementalReplacements
            ),
            spellingCandidates: completionSource.spellingCandidates(
                for: partial,
                language: checkerLanguage
            ),
            completionCandidates: completionSource.completions(
                for: partial,
                language: checkerLanguage,
                supplementalReplacements: supplementalReplacements
            ),
            languageCode: languageCode,
            limit: limit
        )
    }

    private func keyboardSuggestion(
        from suggestion: TextSuggestion,
        context: String
    ) -> KeyboardSuggestion? {
        let kind: KeyboardSuggestion.Kind
        let idPrefix: String
        switch suggestion.kind {
        case .correction:
            kind = .correction
            idPrefix = "correction"
        case .completion:
            kind = .completion
            idPrefix = "completion"
        case .prediction:
            kind = .prediction
            idPrefix = "prediction"
        }

        let rawOriginal = kind == .correction
            ? TypingContextAnalyzer.rawTrailingWord(in: context)
            : nil
        let deleteCount = rawOriginal?.count ?? suggestion.replacementLength
        let insertion = suggestion.text + " "
        let precedingContext = String(context.dropLast(deleteCount))
        let automaticReplacement: AutomaticSuggestionReplacement?
        if let rawOriginal,
           let source = suggestion.automaticCorrectionSource {
            automaticReplacement = AutomaticSuggestionReplacement(
                originalText: rawOriginal,
                replacementText: suggestion.text,
                boundary: " ",
                precedingContext: precedingContext,
                source: source
            )
        } else {
            automaticReplacement = nil
        }

        guard let receipt = suggestionMutationReceipt(
            contextBeforeInput: context,
            deleteCount: deleteCount
        ) else { return nil }
        return KeyboardSuggestion(
            id: "\(idPrefix)-\(suggestion.text)",
            kind: kind,
            display: suggestion.text,
            deleteCount: deleteCount,
            insertion: insertion,
            originalText: rawOriginal,
            automaticReplacement: automaticReplacement,
            mutationReceipt: receipt
        )
    }

    private func emojiSuggestion(
        for analysis: TypingContextAnalysis,
        context: String
    ) -> KeyboardSuggestion? {
        switch analysis.mode {
        case .typingWord(let partial):
            guard let emoji = SuggestionEmojiMap.emoji(for: partial) else { return nil }
            guard let receipt = suggestionMutationReceipt(
                contextBeforeInput: context,
                deleteCount: partial.count
            ) else { return nil }
            return KeyboardSuggestion(
                id: "emoji-\(emoji)",
                kind: .emoji,
                display: emoji,
                deleteCount: partial.count,
                insertion: emoji,
                mutationReceipt: receipt
            )
        case .betweenWords(let lastWord):
            guard let lastWord,
                  let emoji = SuggestionEmojiMap.emoji(for: lastWord),
                  let replacementTarget = TypingContextAnalyzer
                      .rawTrailingWordAndHorizontalWhitespace(in: context) else {
                return nil
            }
            let deleteCount = replacementTarget.count
            guard let receipt = suggestionMutationReceipt(
                contextBeforeInput: context,
                deleteCount: deleteCount
            ) else { return nil }
            return KeyboardSuggestion(
                id: "emoji-\(emoji)",
                kind: .emoji,
                display: emoji,
                deleteCount: deleteCount,
                insertion: emoji + " ",
                mutationReceipt: receipt
            )
        case .empty:
            return nil
        }
    }

    private func suggestionMutationReceipt(
        contextBeforeInput: String,
        deleteCount: Int,
        targetOwnership: KeyboardSuggestionTargetOwnership = .contextDerived
    ) -> KeyboardSuggestionMutationReceipt? {
        guard let delegate,
              deleteCount >= 0,
              deleteCount <= contextBeforeInput.count else { return nil }
        let deletedSuffix = String(contextBeforeInput.suffix(deleteCount))
        let resolvedTargetOwnership: KeyboardSuggestionTargetOwnership
        if targetOwnership == .keyboardOwned
            || (
                deleteCount > 0
                    && currentWordTapTargetStartedAtProvenBoundary
                    && TapWordDecoder.hasExactKeyboardOwnership(
                        currentWordTaps,
                        visibleWord: deletedSuffix
                    )
            ) {
            resolvedTargetOwnership = .keyboardOwned
        } else {
            resolvedTargetOwnership = .contextDerived
        }
        return KeyboardSuggestionMutationReceipt(
            fieldEpoch: editorFieldEpoch,
            fieldIdentifier: delegate.editorFieldIdentifier,
            languageCode: activeKeyboardLanguageCode,
            contextBeforeInput: contextBeforeInput,
            deleteCount: deleteCount,
            targetOwnership: resolvedTargetOwnership
        )
    }

    /// Corrects (when enabled) and learns the word being finished before its
    /// boundary is inserted, so both actions share the same ranking seam.
    private func commitCurrentWord() -> LocalAutomaticCorrection? {
        guard editorCapabilities.automaticCorrection.isAllowed
                || editorCapabilities.personalizedLearning.isAllowed else {
            observedTextSuffix.clear()
            return nil
        }
        guard let context = intelligenceContextBeforeInput() else { return nil }
        if observedTextSuffix.consumeIfUnchanged(contextBeforeInput: context) {
            return nil
        }
        guard let rawWord = TypingContextAnalyzer.rawTrailingWord(in: context),
              case .typingWord(let word) = TypingContextAnalyzer.analyze(context).mode else {
            return nil
        }
        let hasExactKeyboardOwnership =
            currentWordTapTargetStartedAtProvenBoundary
            && TapWordDecoder.hasExactKeyboardOwnership(
                currentWordTaps,
                visibleWord: rawWord
            )
        guard KeyboardWordTargetOwnershipPolicy.isCompleteTarget(
            contextBeforeInput: context,
            target: rawWord,
            hasExactKeyboardOwnership: hasExactKeyboardOwnership
        ) else {
            return nil
        }
        let prefix = String(context.dropLast(rawWord.count))

        if activePracticeSession == nil,
           cachedSettings.automaticallyCorrectWords,
           editorCapabilities.automaticCorrection.isAllowed {
            if let correction = latticeCorrection(
                for: word,
                precedingContext: prefix,
                languageCode: activeKeyboardLanguageCode
            ) {
                guard replaceCurrentWord(
                    rawWord,
                    with: correction,
                    expectedContextBeforeInput: context
                ) else { return nil }
                return LocalAutomaticCorrection(
                    originalText: rawWord,
                    replacementText: correction,
                    precedingContext: prefix,
                    languageCode: activeKeyboardLanguageCode,
                    source: .tapLattice
                )
            }
        }

        if activePracticeSession == nil,
           cachedSettings.automaticallyCorrectWords,
           editorCapabilities.automaticCorrection.isAllowed,
           let correction = localTextSuggestions(for: context, limit: 3)
               .first(where: { $0.kind == .correction }) {
            guard replaceCurrentWord(
                rawWord,
                with: correction.text,
                expectedContextBeforeInput: context
            ) else { return nil }
            return LocalAutomaticCorrection(
                originalText: rawWord,
                replacementText: correction.text,
                precedingContext: prefix,
                languageCode: activeKeyboardLanguageCode,
                source: correction.automaticCorrectionSource ?? .spelling
            )
        }

        observePersonalCommittedText(
            rawWord,
            precededBy: prefix,
            languageCode: activeKeyboardLanguageCode
        )
        return nil
    }

    private func latticeCorrection(
        for visibleWord: String,
        precedingContext: String,
        languageCode: String?
    ) -> String? {
        guard currentWordTaps.count == TapWordDecoder.expectedTapCount(
            for: visibleWord
        ),
              textIntelligence.usageCount(
                  for: visibleWord,
                  languageCode: languageCode
              ) < 3 else { return nil }
        let result = tapWordDecoder.decode(
            currentWordTaps,
            previousWord: lastWord(in: precedingContext),
            languageCode: languageCode,
            limit: 5
        )
        guard let best = TapWordAcceptancePolicy.automatic.acceptedCandidate(
            from: result
        ) else {
            return nil
        }
        let candidate = matchingCapitalization(
            of: best.word,
            to: visibleWord
        )
        guard candidate.caseInsensitiveCompare(visibleWord) != .orderedSame,
              !textIntelligence.isCorrectionSuppressed(
                  typed: visibleWord,
                  suggestion: candidate,
                  languageCode: languageCode
              ) else {
            return nil
        }
        return candidate
    }

    private func replaceCurrentWord(
        _ original: String,
        with replacement: String,
        expectedContextBeforeInput: String
    ) -> Bool {
        guard let delegate,
              intelligenceContextBeforeInput() == expectedContextBeforeInput,
              expectedContextBeforeInput.hasSuffix(original) else {
            return false
        }
        for _ in original {
            delegate.deleteBackward()
        }
        delegate.insertText(replacement)
        return true
    }

    private func beginAutomaticCorrectionReceipt(
        _ correction: LocalAutomaticCorrection,
        boundary: String
    ) {
        guard let delegate else {
            observePersonalCommittedText(
                correction.replacementText,
                precededBy: correction.precedingContext,
                languageCode: correction.languageCode
            )
            return
        }
        correctionCompositionSession.synchronizeField(
            identifier: delegate.editorFieldIdentifier
        )
        let editor = KeyboardInputCorrectionEditorAdapter(
            delegate: delegate,
            contextAccess: editorCapabilities.readContext
        )
        let now = ProcessInfo.processInfo.systemUptime * 1_000
        let effect = correctionCompositionSession.recordAutomaticApplication(
            in: editor,
            originalText: correction.originalText,
            replacementText: correction.replacementText,
            boundary: boundary,
            precedingContext: correction.precedingContext,
            languageCode: correction.languageCode,
            source: correction.source,
            atMilliseconds: now
        )
        activateAutomaticCorrectionReceipt(
            correction,
            effect: effect,
            atMilliseconds: now
        )
    }

    private func activateAutomaticCorrectionReceipt(
        _ correction: LocalAutomaticCorrection,
        effect: CorrectionCompositionEffect,
        atMilliseconds now: Double
    ) {
        guard !effect.ignored,
              let receiptID = correctionCompositionSession.snapshot.receiptID else {
            observePersonalCommittedText(
                correction.replacementText,
                precededBy: correction.precedingContext,
                languageCode: correction.languageCode
            )
            return
        }
        automaticCorrectionOriginalText =
            correctionCompositionSession.snapshot.originalText
        automaticCorrectionExpiryTask?.cancel()
        automaticCorrectionExpiryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard let self,
                  correctionCompositionSession.snapshot.receiptID == receiptID,
                  let currentDelegate = self.delegate else { return }
            let expiryEffect = correctionCompositionSession.advanceTime(
                toMilliseconds: now + 3_000,
                in: KeyboardInputCorrectionEditorAdapter(
                    delegate: currentDelegate,
                    contextAccess: editorCapabilities.readContext
                )
            )
            automaticCorrectionOriginalText = nil
            automaticCorrectionExpiryTask = nil
            acceptCompositionLearning(expiryEffect)
        }
    }

    @discardableResult
    private func revertAutomaticCorrectionIfPossible(
        mode: AutomaticCorrectionRevertMode
    ) -> Bool {
        guard correctionCompositionSession.snapshot.receiptMode == .automatic,
              let delegate else {
            clearAutomaticCorrectionReceipt(acceptLearning: false)
            return false
        }
        let editor = KeyboardInputCorrectionEditorAdapter(
            delegate: delegate,
            contextAccess: editorCapabilities.readContext
        )
        let effect = switch mode {
        case .immediateBackspace:
            correctionCompositionSession.backspace(in: editor)
        case .visibleUndo:
            correctionCompositionSession.visibleRevert(in: editor)
        }
        automaticCorrectionOriginalText = nil
        automaticCorrectionExpiryTask?.cancel()
        automaticCorrectionExpiryTask = nil
        if allowsPersonalLanguageLearning, let rejection = effect.rejection {
            textIntelligence.rejectCommittedWord(
                rejection.rejectedText,
                precededBy: lastWord(in: rejection.precedingContext),
                languageCode: rejection.languageCode
            )
            observePersonalCommittedText(
                rejection.restoredText,
                precededBy: rejection.precedingContext,
                languageCode: rejection.languageCode
            )
        }
        if let restoredText = effect.rejection?.restoredText {
            present(.automaticCorrectionReverted(restoredText))
        }
        return effect.didMutateEditor
    }

    func undoAutomaticCorrection() {
        cancelCorrection()
        clearCorrectionUndo(acceptLearning: false)
        guard revertAutomaticCorrectionIfPossible(mode: .visibleUndo) else {
            present(.staleContext)
            return
        }
        lastTypingDecision = nil
        pendingRejectedDecision = nil
        currentWordTaps.removeAll(keepingCapacity: true)
        observedTextSuffix.clear()
        refreshAfterEditorMutation()
    }

    private func clearAutomaticCorrectionReceipt(acceptLearning: Bool) {
        automaticCorrectionExpiryTask?.cancel()
        automaticCorrectionExpiryTask = nil
        automaticCorrectionOriginalText = nil
        guard correctionCompositionSession.snapshot.receiptMode == .automatic else { return }
        guard let delegate else {
            correctionCompositionSession.externalEditObserved()
            return
        }
        let effect = correctionCompositionSession.finishActiveReceipt(
            in: KeyboardInputCorrectionEditorAdapter(
                delegate: delegate,
                contextAccess: editorCapabilities.readContext
            ),
            acceptLearning: acceptLearning
        )
        acceptCompositionLearning(effect)
    }

    private func acceptCompositionLearning(_ effect: CorrectionCompositionEffect) {
        guard allowsPersonalLanguageLearning,
              let learning = effect.acceptedLearning else { return }
        observePersonalCommittedText(
            learning.text,
            precededBy: learning.precedingContext,
            languageCode: learning.languageCode
        )
    }

    private func matchingCapitalization(of candidate: String, to source: String) -> String {
        if source.contains(where: { $0.isLetter }) &&
            source.allSatisfy({ !$0.isLetter || $0.isUppercase }) {
            return candidate.uppercased()
        }
        if source.first?.isUppercase == true {
            return capitalized(candidate.lowercased())
        }
        return candidate.lowercased()
    }

    func documentContextDidChange() {
        editorFieldEpoch &+= 1
        if let delegate {
            correctionCompositionSession.synchronizeField(
                identifier: delegate.editorFieldIdentifier
            )
        }
        let invalidatedProposal = pendingCorrectionProposal != nil
        if invalidatedProposal {
            clearCorrectionProposal()
        }
        shouldPresentStaleContextAfterRefresh =
            shouldPresentStaleContextAfterRefresh || invalidatedProposal
        if correctionTask != nil {
            cancelCorrection()
            setQuietly(baselineStatus)
        }
        scheduleDocumentContextRefresh()
    }

    private func reconcileDocumentContext() {
        let previousCapabilities = editorCapabilities
        refreshEditorCapabilities()
        let context = intelligenceContextBeforeInput()
        refreshAutomaticShiftState(fromContext: context)
        if previousCapabilities != editorCapabilities {
            baselineStatus = availabilityStatus()
        }
        if correctionCompositionSession.snapshot.receiptMode == .automatic,
           let delegate {
            let invalidated = correctionCompositionSession.invalidateIfEditorChanged(
                KeyboardInputCorrectionEditorAdapter(
                    delegate: delegate,
                    contextAccess: editorCapabilities.readContext
                )
            )
            if invalidated {
                automaticCorrectionOriginalText = nil
                automaticCorrectionExpiryTask?.cancel()
                automaticCorrectionExpiryTask = nil
            }
        }
        if correctionCompositionSession.snapshot.receiptMode == .automatic,
           delegate == nil {
                clearAutomaticCorrectionReceipt(acceptLearning: false)
        }
        if let pendingCorrectionUndo,
           !editorCapabilities.readContext.isAllowed
            || delegate?.canUndoCorrection(pendingCorrectionUndo) != true {
            clearCorrectionUndo(acceptLearning: false)
        }
        observedTextSuffix.retainIfUnchanged(
            contextBeforeInput: context
        )
        let currentWordLength: Int
        if case .typingWord(let word) = TypingContextAnalyzer
            .analyze(context).mode {
            currentWordLength = TapWordDecoder.expectedTapCount(for: word) ?? 0
        } else {
            currentWordLength = 0
        }
        if currentWordTaps.count != currentWordLength {
            currentWordTaps.removeAll(keepingCapacity: true)
        }
        updateSuggestions(context: context)
        refreshPendingTranscriptAvailability()
        if shouldPresentStaleContextAfterRefresh {
            shouldPresentStaleContextAfterRefresh = false
            present(.staleContext)
        }
    }

    func deactivate() {
        editorFieldEpoch &+= 1
        typingRefreshTask?.cancel()
        typingRefreshTask = nil
        shouldPresentStaleContextAfterRefresh = false
        needsDocumentContextRefresh = false
        cancelCorrection()
        clearCorrectionProposal()
        clearCorrectionUndo()
        clearAutomaticCorrectionReceipt(acceptLearning: false)
        persistAdaptiveProfileIfNeeded(force: true)
        lastTypingDecision = nil
        pendingRejectedDecision = nil
        currentWordTaps.removeAll(keepingCapacity: true)
        textIntelligenceBacking?.persist()
        setQuietly(baselineStatus)
    }

    func showAppleDictationGuidance() {
        present(.appleDictationGuidance)
    }

    func showSettingsGuidance() {
        present(.settingsGuidance)
    }

    func correctCurrentText(intent: BuddyRewriteIntent = .fix) {
        correctText(
            intent: intent,
            requestScope: .currentText,
            appliesImmediately: false
        )
    }

    func correctAllText() {
        correctText(
            intent: .fix,
            requestScope: .allText,
            appliesImmediately: true
        )
    }

    private func correctText(
        intent: BuddyRewriteIntent,
        requestScope: DocumentCorrectionRequestScope,
        appliesImmediately: Bool
    ) {
        refreshAvailability()
        cancelCorrection()
        clearCorrectionProposal()
        clearAutomaticCorrectionReceipt(acceptLearning: true)
        clearCorrectionUndo()

        guard requireCapability(editorCapabilities.cloudCorrection),
              requireCapability(editorCapabilities.readContext) else { return }
        let settings = cachedSettings

        guard let snapshot = delegate?.captureCorrectionSnapshot(
            requestScope: requestScope
        ) else {
            present(.noText)
            return
        }
        if let delegate {
            correctionCompositionSession.synchronizeField(
                identifier: delegate.editorFieldIdentifier
            )
        }
        let correctionAsyncStamp = correctionCompositionSession.captureAsyncStamp()

        guard let clientID = preferences?.installationIdentifier() else {
            present(.error("BuddyGrammar could not open its shared container."))
            return
        }

        let requestID = UUID()
        let languageCode = activeKeyboardLanguageCode
        correctionRequestID = requestID
        present(.correcting)

        correctionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let corrected = try await correctionClient.correct(
                    text: snapshot.candidate.requestText,
                    clientID: clientID,
                    modelID: settings.activeOpenRouterModelID,
                    instruction: intent.instruction(
                        appendingTo: settings.correctionInstruction
                    )
                )
                try Task.checkCancellation()
                guard correctionRequestID == requestID,
                      correctionCompositionSession.isFresh(correctionAsyncStamp) else {
                    return
                }

                let replacement = snapshot.candidate.replacement(with: corrected)
                let scope: KeyboardCorrectionScope = switch snapshot.target {
                case .selection: .selection
                case .currentSentence: .currentSentence
                case .allText: .allText
                }
                let proposal = ReviewableCorrectionProposal(
                    intent: intent,
                    originalText: snapshot.candidate.capturedText,
                    proposedText: replacement
                )
                pendingCorrectionProposal = PendingCorrectionProposal(
                    proposal: proposal,
                    snapshot: snapshot,
                    scope: scope,
                    languageCode: languageCode,
                    undoDuration: settings.correctionUndoDuration
                )
                correctionProposal = proposal
                correctionProposalScope = scope
                correctionTask = nil
                correctionRequestID = nil
                if appliesImmediately {
                    acceptCorrectionProposal()
                } else {
                    present(.correctionProposalReady)
                }
            } catch is CancellationError {
                // Cancellation is expected whenever the document changes.
            } catch {
                guard correctionRequestID == requestID else { return }
                correctionTask = nil
                correctionRequestID = nil
                present(.error(error.localizedDescription))
            }
        }
    }

    func acceptCorrectionProposal() {
        refreshEditorCapabilities()
        guard requireCapability(editorCapabilities.cloudCorrection),
              requireCapability(editorCapabilities.readContext) else {
            clearCorrectionProposal()
            return
        }
        guard let pendingCorrectionProposal else { return }
        clearCorrectionProposal()
        guard pendingCorrectionProposal.proposal.hasChanges else {
            present(.correctionProposalDismissed)
            return
        }

        let appliedCorrection = delegate?.applyCorrection(
            pendingCorrectionProposal.proposal.proposedText,
            to: pendingCorrectionProposal.snapshot
        )
        guard let appliedCorrection else {
            present(.staleContext)
            return
        }

        observedTextSuffix.clear()
        let learningContext: String?
        switch pendingCorrectionProposal.snapshot.target {
        case .selection:
            learningContext = pendingCorrectionProposal.snapshot.contextBeforeInput
        case .currentSentence, .allText:
            learningContext = nil
        }
        beginCorrectionUndo(
            appliedCorrection,
            duration: pendingCorrectionProposal.undoDuration,
            learning: DeferredCorrectionLearning(
                text: pendingCorrectionProposal.proposal.proposedText,
                precedingContext: learningContext,
                languageCode: pendingCorrectionProposal.languageCode,
                resultingContext: appliedCorrection.contextBeforeInput
            )
        )
        present(.corrected)
        refreshAfterEditorMutation()
    }

    func dismissCorrectionProposal() {
        guard pendingCorrectionProposal != nil else { return }
        clearCorrectionProposal()
        present(.correctionProposalDismissed)
    }

    func undoLastCorrection() {
        refreshEditorCapabilities()
        guard requireCapability(editorCapabilities.readContext) else {
            clearCorrectionUndo(acceptLearning: false)
            return
        }
        guard let pendingCorrectionUndo, let delegate else { return }
        let effect = correctionCompositionSession.visibleRevert(
            in: AppliedCorrectionEditorAdapter(
                delegate: delegate,
                correction: pendingCorrectionUndo,
                contextAccess: editorCapabilities.readContext
            )
        )
        undoDismissTask?.cancel()
        undoDismissTask = nil
        deferredCorrectionLearning = nil
        self.pendingCorrectionUndo = nil
        canUndoCorrection = false
        observedTextSuffix.clear()
        let didUndo = effect.didMutateEditor
        present(didUndo ? .correctionUndone : .staleContext)
        if didUndo {
            refreshAfterEditorMutation()
        } else {
            refreshSuggestions()
        }
    }

    func insertPendingTranscript() {
        refreshAvailability()

        guard requireCapability(editorCapabilities.transcriptInsertion) else { return }
        cancelCorrectionForLocalEdit()

        guard let preferences else {
            present(.error("BuddyGrammar could not open its shared container."))
            return
        }

        guard let transcript = preferences.loadPendingTranscript(),
              !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hasPendingTranscript = false
            present(.noPendingTranscript)
            return
        }

        let context = intelligenceContextBeforeInput()
        guard commitRecognizedText(
            transcript.text,
            context: context,
            languageCode: transcript.languageCode
        ) else {
            present(.staleContext)
            return
        }
        preferences.clearPendingTranscript()
        hasPendingTranscript = false
        present(.transcriptInserted)
    }

    private func capitalized(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first).uppercased() + word.dropFirst()
    }

    private func refreshPendingTranscriptAvailability() {
        guard editorCapabilities.transcriptInsertion.isAllowed else {
            hasPendingTranscript = false
            return
        }
        hasPendingTranscript = preferences?.loadPendingTranscript().map {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
    }

    private func beginCorrectionUndo(
        _ correction: AppliedCorrection,
        duration: TimeInterval,
        learning: DeferredCorrectionLearning
    ) {
        guard let delegate else { return }
        let effect = correctionCompositionSession.recordExplicitApplication(
            in: AppliedCorrectionEditorAdapter(
                delegate: delegate,
                correction: correction,
                contextAccess: editorCapabilities.readContext
            ),
            originalText: correction.originalText,
            replacementText: correction.replacementText,
            source: "buddyFix",
            precedingContext: learning.precedingContext ?? "",
            languageCode: learning.languageCode,
            atMilliseconds: ProcessInfo.processInfo.systemUptime * 1_000,
            receiptLifetimeMilliseconds: duration * 1_000
        )
        guard !effect.ignored else { return }
        pendingCorrectionUndo = correction
        deferredCorrectionLearning = learning
        canUndoCorrection = true
        undoDismissTask?.cancel()
        undoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.clearCorrectionUndo()
        }
    }

    private func clearCorrectionUndo(acceptLearning: Bool = true) {
        undoDismissTask?.cancel()
        undoDismissTask = nil
        let learning = deferredCorrectionLearning
        let correction = pendingCorrectionUndo
        let acceptance: CorrectionCompositionEffect
        if correctionCompositionSession.snapshot.receiptMode == .explicit,
           let correction,
           let delegate {
            acceptance = correctionCompositionSession.finishActiveReceipt(
                in: AppliedCorrectionEditorAdapter(
                    delegate: delegate,
                    correction: correction,
                    contextAccess: editorCapabilities.readContext
                ),
                acceptLearning: acceptLearning
            )
        } else {
            if correctionCompositionSession.snapshot.receiptMode == .explicit {
                correctionCompositionSession.externalEditObserved()
            }
            acceptance = CorrectionCompositionEffect()
        }
        deferredCorrectionLearning = nil
        pendingCorrectionUndo = nil
        canUndoCorrection = false

        guard acceptLearning,
              acceptance.acceptedLearning != nil,
              let learning else { return }
        observePersonalCommittedText(
            learning.text,
            precededBy: learning.precedingContext,
            languageCode: learning.languageCode
        )
        if intelligenceContextBeforeInput() == learning.resultingContext {
            observedTextSuffix.observe(
                committedText: learning.text,
                contextBeforeInput: learning.resultingContext
            )
        }
    }

    private func present(_ newStatus: KeyboardStatus) {
        status = newStatus
        isStatusPresented = true
        statusDismissTask?.cancel()
        guard newStatus != .correcting else { return }

        statusDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.isStatusPresented = false
        }
    }

    private func setQuietly(_ newStatus: KeyboardStatus) {
        status = newStatus
        isStatusPresented = false
        statusDismissTask?.cancel()
    }

    private func cancelCorrectionForLocalEdit() {
        clearAutomaticCorrectionReceipt(acceptLearning: true)
        clearCorrectionProposal()
        clearCorrectionUndo()
        let hadCorrection = correctionTask != nil
        cancelCorrection()
        if hadCorrection {
            setQuietly(baselineStatus)
        } else {
            status = baselineStatus
        }
    }

    private func cancelCorrection() {
        correctionTask?.cancel()
        correctionTask = nil
        correctionRequestID = nil
    }

    private func clearCorrectionProposal() {
        pendingCorrectionProposal = nil
        correctionProposal = nil
        correctionProposalScope = nil
    }

    private func availabilityStatus() -> KeyboardStatus {
        switch editorCapabilities.cloudCorrection {
        case .allowed:
            return .ready
        case .denied(.cloudTransportUnavailable):
            return .fullAccessRequired
        case .denied(.cloudProcessingConsentRequired):
            return .cloudConsentRequired
        case .denied(let reason):
            return .capabilityDenied(reason)
        }
    }

    private func refreshAutomaticShiftState(ownedInsertion: String? = nil) {
        guard layoutMode == .letters, !userEnabledCapsLock else { return }
        if let ownedInsertion {
            let shouldShift = KeyboardAutomaticShiftPolicy.shouldShiftAfterOwnedInsertion(
                mode: keyboardAutoCapitalization,
                wasShifted: shiftState.isShifted,
                insertedText: ownedInsertion
            )
            applyAutomaticShift(shouldShift)
        } else {
            refreshAutomaticShiftState(fromContext: intelligenceContextBeforeInput())
        }
    }

    private func refreshAutomaticShiftState(fromContext context: String?) {
        guard layoutMode == .letters, !userEnabledCapsLock else { return }
        let shouldShift = KeyboardAutomaticShiftPolicy.shouldShift(
            mode: keyboardAutoCapitalization,
            contextBeforeInput: context
        )
        applyAutomaticShift(shouldShift)
    }

    private func applyAutomaticShift(_ shouldShift: Bool?) {
        guard let shouldShift else { return }
        switch keyboardAutoCapitalization {
        case .none:
            shiftState = .lowercase
        case .allCharacters:
            shiftState = .capsLock
        case .words, .sentences:
            shiftState = shouldShift ? .uppercase : .lowercase
        }
    }

    private func refreshAfterEditorMutation(ownedInsertion: String? = nil) {
        if let ownedInsertion {
            refreshAutomaticShiftState(ownedInsertion: ownedInsertion)
            scheduleSuggestionsRefresh()
        } else {
            scheduleDocumentContextRefresh()
        }
    }

    private func scheduleSuggestionsRefresh() {
        if needsDocumentContextRefresh {
            scheduleDocumentContextRefresh()
            return
        }
        typingRefreshTask?.cancel()
        typingRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.typingRefreshDelayMilliseconds))
            guard !Task.isCancelled else { return }
            self?.typingRefreshTask = nil
            self?.refreshSuggestions()
        }
    }

    private func scheduleDocumentContextRefresh() {
        needsDocumentContextRefresh = true
        typingRefreshTask?.cancel()
        typingRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.typingRefreshDelayMilliseconds))
            guard !Task.isCancelled else { return }
            self?.typingRefreshTask = nil
            self?.needsDocumentContextRefresh = false
            self?.reconcileDocumentContext()
        }
    }

    private static let typingRefreshDelayMilliseconds = 24
    private static let autocorrectionBoundaryCharacters: Set<String> = [
        ".", ",", "?", "!", ";", ":",
    ]
}

private extension EditorCapabilityDenialReason {
    var keyboardMessage: String {
        switch self {
        case .sensitiveField:
            "Buddy actions are unavailable in secure fields."
        case .structuredField:
            "Buddy actions are unavailable in this structured field."
        case .codeField:
            "Buddy actions are unavailable in code fields."
        case .suggestionsDisabled:
            "This field has disabled suggestions and automatic correction."
        case .personalizedLearningDisabled:
            "This field does not allow personalized learning."
        case .cloudTransportUnavailable:
            "Typing works. Enable Full Access for Buddy actions."
        case .cloudProcessingConsentRequired:
            "Accept cloud processing in BuddyGrammar to use this action."
        case .platformVoiceUnavailable:
            "Use the system keyboard for Apple Dictation."
        case .cursorMovementUnavailable:
            "This field does not allow cursor movement."
        case .sharedContainerUnavailable:
            "Enable Full Access to insert a saved transcript."
        case .contextReadUnavailable:
            "This editor does not expose surrounding text to keyboard intelligence."
        case .compositionUnavailable:
            "This editor does not allow composing text."
        }
    }
}
