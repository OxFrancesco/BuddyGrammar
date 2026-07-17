import BuddyGrammarKit
import Foundation
import Observation
import OSLog
import UIKit

let keyboardDictationLog = Logger(
    subsystem: "com.francescooddo.BuddyGrammar.Keyboard",
    category: "keyboard.dictation"
)

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
    case transcriptInserted
    case startingDictation
    case openingDictation
    case dictationRecording
    case dictationProcessing
    case fullAccessRequired
    case cloudConsentRequired
    case noText
    case noPendingTranscript
    case staleContext
    case error(String)

    var message: String {
        switch self {
        case .ready:
            "Tap ★ to fix the text, or select part of it first."
        case .correcting:
            "Correcting…"
        case .corrected:
            "Correction applied."
        case .correctionUndone:
            "Correction undone."
        case .transcriptInserted:
            "Dictation inserted."
        case .startingDictation:
            "Starting from Dynamic Island…"
        case .openingDictation:
            "Opening BuddyGrammar… Swipe back when the microphone starts."
        case .dictationRecording:
            "Listening… Tap the red stop button when finished."
        case .dictationProcessing:
            "Transcribing and polishing your words…"
        case .fullAccessRequired:
            "Typing works. Enable Full Access for ★ and dictation."
        case .cloudConsentRequired:
            "Accept cloud processing in the BuddyGrammar app to use ★."
        case .noText:
            "Type some text first."
        case .noPendingTranscript:
            "No dictation is waiting. Record one in BuddyGrammar first."
        case .staleContext:
            "The text changed, so the correction was not applied."
        case .error(let message):
            message
        }
    }

    var isError: Bool {
        switch self {
        case .fullAccessRequired, .cloudConsentRequired,
             .noText, .noPendingTranscript, .staleContext, .error:
            true
        case .ready, .correcting, .corrected, .correctionUndone,
             .transcriptInserted, .openingDictation,
             .startingDictation,
             .dictationRecording, .dictationProcessing:
            false
        }
    }
}

enum KeyboardDictationPhase: Equatable {
    case idle
    case launching
    case recording
    case processing
}

enum DocumentCorrectionTarget: Equatable, Sendable {
    case selection
    case currentSentence(charactersAfterCursor: Int)
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
}

@MainActor
protocol KeyboardModelDelegate: AnyObject {
    var keyboardHasFullAccess: Bool { get }
    var contextBeforeInput: String? { get }
    var keyboardLanguage: String { get }
    var allowsAutomaticTextCorrection: Bool { get }
    var allowsPersonalizedLearning: Bool { get }

    func insertText(_ text: String)
    func deleteBackward()
    func captureCorrectionSnapshot() -> DocumentCorrectionSnapshot?
    func applyCorrection(
        _ replacement: String,
        to snapshot: DocumentCorrectionSnapshot
    ) -> AppliedCorrection?
    func canUndoCorrection(_ correction: AppliedCorrection) -> Bool
    func undoCorrection(_ correction: AppliedCorrection) -> Bool
    func openHostApplication(
        _ url: URL,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    )
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

@MainActor
@Observable
final class KeyboardModel {
    var layoutMode: KeyboardLayoutMode = .letters
    var shiftState: KeyboardShiftState = .uppercase
    private(set) var status: KeyboardStatus = .fullAccessRequired
    private(set) var isStatusPresented = true
    private(set) var hasFullAccess = false
    private(set) var suggestions: [KeyboardSuggestion] = []
    private(set) var canUndoCorrection = false
    private(set) var dictationPhase: KeyboardDictationPhase = .idle
    private(set) var hasPendingTranscript = false

    @ObservationIgnored private weak var delegate: KeyboardModelDelegate?
    @ObservationIgnored private let correctionClient: OpenRouterCorrectionClient
    @ObservationIgnored private let handwritingClient: HandwritingRecognitionClient
    @ObservationIgnored private let preferences: SharedPreferences?
    @ObservationIgnored private let adaptiveStore: AdaptiveLearningStore?
    @ObservationIgnored private let completionSource = WordCompletionSource()
    @ObservationIgnored private var correctionTask: Task<Void, Never>?
    @ObservationIgnored private var correctionRequestID: UUID?
    @ObservationIgnored private var statusDismissTask: Task<Void, Never>?
    @ObservationIgnored private var undoDismissTask: Task<Void, Never>?
    @ObservationIgnored private var dictationMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var baselineStatus: KeyboardStatus = .fullAccessRequired
    @ObservationIgnored private var pendingCorrectionUndo: AppliedCorrection?
    @ObservationIgnored private var deferredCorrectionLearning: DeferredCorrectionLearning?
    @ObservationIgnored private var supplementalReplacements: [String: String] = [:]
    @ObservationIgnored private var cachedSwipeEngine: SwipeTypingEngine?
    @ObservationIgnored private var didWarmUpConnection = false
    @ObservationIgnored private let textIntelligence: TextIntelligence
    @ObservationIgnored private var observedTextSuffix = ObservedTextSuffix()
    @ObservationIgnored private var typingIntelligence: TypingIntelligence
    @ObservationIgnored private let tapWordDecoder = TapWordDecoder()
    @ObservationIgnored private var currentWordTaps: [TapWordLatticeTap] = []
    @ObservationIgnored private var activePracticeSession: ActivePracticeSession?
    @ObservationIgnored private var lastTypingDecision: TypingDecision?
    @ObservationIgnored private var pendingRejectedDecision: TypingDecision?
    @ObservationIgnored private var adaptiveProfileIsDirty = false
    @ObservationIgnored private var observationsSinceAdaptiveSave = 0

    init(
        correctionClient: OpenRouterCorrectionClient = OpenRouterCorrectionClient(),
        handwritingClient: HandwritingRecognitionClient = HandwritingRecognitionClient(),
        preferences: SharedPreferences? = SharedPreferences(),
        adaptiveStore: AdaptiveLearningStore? = AdaptiveLearningStore(),
        textIntelligence: TextIntelligence? = nil
    ) {
        self.correctionClient = correctionClient
        self.handwritingClient = handwritingClient
        self.preferences = preferences
        self.adaptiveStore = adaptiveStore
        self.textIntelligence = textIntelligence ?? TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(
                defaults: UserDefaults(
                    suiteName: BuddyGrammarConfiguration.appGroupIdentifier
                ) ?? .standard
            )
        )
        self.typingIntelligence = TypingIntelligence(
            profile: adaptiveStore?.loadTypingProfile() ?? TypingProfile(),
            policy: .literal
        )
    }

    func connect(delegate: KeyboardModelDelegate) {
        self.delegate = delegate
        activate()
    }

    func activate() {
        refreshAdaptiveState()
        refreshAvailability()
        refreshPendingTranscriptAvailability()
        refreshSuggestions()
        refreshKeyboardDictationSession()
        startDictationMonitor()
        warmUpCorrectionConnectionIfNeeded()
    }

    private func warmUpCorrectionConnectionIfNeeded() {
        guard hasFullAccess, !didWarmUpConnection else { return }
        didWarmUpConnection = true
        Task { [correctionClient] in
            await correctionClient.warmUpConnection()
        }
    }

    func refreshAvailability() {
        hasFullAccess = delegate?.keyboardHasFullAccess ?? false

        guard hasFullAccess else {
            cancelCorrection()
            clearCorrectionUndo()
            baselineStatus = .fullAccessRequired
            present(baselineStatus)
            return
        }

        let shouldPreserveCorrectionStatus = correctionTask != nil
        baselineStatus = availabilityStatus()
        if !shouldPreserveCorrectionStatus {
            present(baselineStatus)
        }
    }

    func insertCharacter(_ character: String) {
        lastTypingDecision = nil
        pendingRejectedDecision = nil
        cancelCorrectionForLocalEdit()
        if Self.autocorrectionBoundaryCharacters.contains(character) {
            commitCurrentWord()
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
        delegate?.insertText(output)

        if layoutMode == .letters, shiftState == .uppercase {
            shiftState = .lowercase
        }
        refreshSuggestions()
    }

    /// Resolves a physical touch without changing the visible keyboard. The
    /// coordinate is already normalized into QWERTY key-space by the view.
    func insertLetter(
        at keySpacePoint: CGPoint,
        literalKey: Character,
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        configureTypingPolicy()
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

        let context = delegate?.contextBeforeInput ?? ""
        let decision = typingIntelligence.resolve(
            tap: tap,
            context: TypingContext(
                rawText: context,
                languageCode: delegate?.keyboardLanguage
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

        currentWordTaps.append(TapWordLatticeTap(decision: decision))
        insertCharacter(String(decision.key))
        lastTypingDecision = decision
    }

    /// Accessibility activation is intentionally literal: VoiceOver users
    /// selected a named key rather than an ambiguous point between keys.
    func insertLiteralCharacter(_ character: String) {
        lastTypingDecision = nil
        pendingRejectedDecision = nil
        if let key = character.first,
           character.count == 1,
           key.isLetter {
            currentWordTaps.append(
                TapWordLatticeTap(
                    literalKey: key,
                    resolvedKey: key,
                    candidates: [TypingCandidate(key: key, confidence: 1)]
                )
            )
        }
        insertCharacter(character)
    }

    func insertSpace() {
        lastTypingDecision = nil
        pendingRejectedDecision = nil
        cancelCorrectionForLocalEdit()
        commitCurrentWord()
        currentWordTaps.removeAll(keepingCapacity: true)
        delegate?.insertText(" ")
        refreshSuggestions()
    }

    func insertReturn() {
        lastTypingDecision = nil
        pendingRejectedDecision = nil
        cancelCorrectionForLocalEdit()
        commitCurrentWord()
        currentWordTaps.removeAll(keepingCapacity: true)
        delegate?.insertText("\n")
        if layoutMode == .letters, shiftState == .lowercase {
            shiftState = .uppercase
        }
        refreshSuggestions()
    }

    func deleteBackward() {
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
        refreshSuggestions()
    }

    func toggleShift() {
        shiftState = shiftState == .lowercase ? .uppercase : .lowercase
    }

    func activateCapsLock() {
        shiftState = .capsLock
    }

    func setLayout(_ mode: KeyboardLayoutMode) {
        cancelCorrectionForLocalEdit()
        currentWordTaps.removeAll(keepingCapacity: true)
        layoutMode = mode
        refreshSuggestions()
    }

    func toggleLayout() {
        setLayout(layoutMode == .letters ? .numbers : .letters)
    }

    func toggleSymbolPlane() {
        setLayout(layoutMode == .symbols ? .numbers : .symbols)
    }

    func insertSuggestion(_ suggestion: KeyboardSuggestion) {
        cancelCorrectionForLocalEdit()
        observedTextSuffix.clear()
        currentWordTaps.removeAll(keepingCapacity: true)
        let context = delegate?.contextBeforeInput ?? ""
        let prefix = String(context.dropLast(suggestion.deleteCount))
        for _ in 0..<suggestion.deleteCount {
            delegate?.deleteBackward()
        }
        delegate?.insertText(suggestion.insertion)
        if suggestion.kind != .emoji {
            observePersonalCommittedText(
                suggestion.insertion,
                precededBy: prefix,
                languageCode: delegate?.keyboardLanguage
            )
            observedTextSuffix.observe(
                committedText: suggestion.insertion,
                contextBeforeInput: prefix + suggestion.insertion
            )
        }
        if layoutMode == .letters, shiftState == .uppercase {
            shiftState = .lowercase
        }
        refreshSuggestions()
    }

    func insertEmoji(_ emoji: String) {
        cancelCorrectionForLocalEdit()
        observedTextSuffix.clear()
        currentWordTaps.removeAll(keepingCapacity: true)
        delegate?.insertText(emoji)
        refreshSuggestions()
    }

    func insertRecognizedText(_ text: String) {
        cancelCorrectionForLocalEdit()
        let context = delegate?.contextBeforeInput
        let formatted = HandwritingTextFormatter.textForInsertion(
            text,
            contextBeforeInput: context,
            languageCode: delegate?.keyboardLanguage
        )
        commitRecognizedText(formatted, context: context)
        refreshSuggestions()
    }

    private func insertDictatedText(
        _ text: String,
        languageCode: String? = nil
    ) {
        cancelCorrectionForLocalEdit()
        let context = delegate?.contextBeforeInput
        commitRecognizedText(
            text,
            context: context,
            languageCode: languageCode
        )
        refreshSuggestions()
    }

    private func commitRecognizedText(
        _ text: String,
        context: String?,
        languageCode: String? = nil
    ) {
        observedTextSuffix.clear()
        currentWordTaps.removeAll(keepingCapacity: true)
        let whitespaceToDelete = RecognizedTextFormatter.whitespaceToDeleteBefore(
            text,
            contextBeforeInput: context
        )
        for _ in 0..<whitespaceToDelete {
            delegate?.deleteBackward()
        }
        let retainedContext = context.map {
            String($0.dropLast(whitespaceToDelete))
        }
        let insertion = RecognizedTextFormatter.textForInsertion(
            text,
            contextBeforeInput: retainedContext
        )
        guard !insertion.isEmpty else { return }
        delegate?.insertText(insertion)
        observePersonalCommittedText(
            insertion,
            precededBy: retainedContext,
            languageCode: languageCode ?? delegate?.keyboardLanguage
        )
        observedTextSuffix.observe(
            committedText: insertion,
            contextBeforeInput: (retainedContext ?? "") + insertion
        )
    }

    func updateSupplementaryLexicon(_ lexicon: UILexicon) {
        supplementalReplacements = Dictionary(
            lexicon.entries.map { ($0.userInput.lowercased(), $0.documentText) },
            uniquingKeysWith: { first, _ in first }
        )
        cachedSwipeEngine = nil
    }

    func commitSwipe(path: [CGPoint]) {
        guard layoutMode == .letters, path.count >= 2 else { return }
        let context = delegate?.contextBeforeInput
        let candidates = swipeEngine().candidates(
            forKeySpacePath: path,
            limit: 3,
            previousWord: lastWord(in: context)
        )
        guard let best = candidates.first else { return }

        cancelCorrectionForLocalEdit()
        currentWordTaps.removeAll(keepingCapacity: true)
        let word = applyingShift(to: best)
        commitRecognizedText(word, context: context)
        if shiftState == .uppercase {
            shiftState = .lowercase
        }

        // Offer runner-up replacements only when the host editor allows
        // dictionary intelligence. Structured and no-suggestion fields must
        // stay free of candidates even after a direct swipe gesture.
        if activePracticeSession == nil,
           delegate?.allowsAutomaticTextCorrection == true {
            suggestions = candidates.dropFirst().map { alternate in
                let display = applyingShift(to: alternate, matching: word)
                return KeyboardSuggestion(
                    id: "swipe-\(alternate)",
                    kind: .completion,
                    display: display,
                    deleteCount: word.count,
                    insertion: display
                )
            }
        } else {
            suggestions = []
        }
    }

    private func lastWord(in context: String?) -> String? {
        context?
            .split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .last
            .map(String.init)
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

    private func refreshAdaptiveState() {
        activePracticeSession = adaptiveStore?.loadActivePracticeSession()
        if !adaptiveProfileIsDirty {
            typingIntelligence = TypingIntelligence(
                profile: adaptiveStore?.loadTypingProfile() ?? typingIntelligence.snapshot,
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
        let settings = preferences?.loadSettings() ?? .default
        if activePracticeSession != nil {
            return settings.adaptiveTypingEnabled ? .practice : .literal
        }
        guard settings.adaptiveTypingEnabled,
              delegate?.allowsAutomaticTextCorrection == true else {
            return .literal
        }
        return delegate?.allowsPersonalizedLearning == true
            ? .personalizedLearning
            : .personalizedReadOnly
    }

    private func expectedPracticeKey(atResponseLength responseLength: Int) -> Character? {
        let settings = preferences?.loadSettings() ?? .default
        guard settings.personalizedPracticeEnabled,
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
        adaptiveProfileIsDirty = true
        observationsSinceAdaptiveSave += 1
        if observationsSinceAdaptiveSave >= 8 {
            persistAdaptiveProfileIfNeeded()
        }
    }

    private func persistAdaptiveProfileIfNeeded(force: Bool = false) {
        guard adaptiveProfileIsDirty, force || observationsSinceAdaptiveSave >= 8 else {
            return
        }
        do {
            try adaptiveStore?.saveTypingProfile(typingIntelligence.snapshot)
            adaptiveProfileIsDirty = false
            observationsSinceAdaptiveSave = 0
        } catch {
            // Typing must never block or fail because aggregate persistence did.
        }
    }

    private var allowsPersonalLanguageLearning: Bool {
        activePracticeSession == nil
            && delegate?.allowsPersonalizedLearning == true
    }

    private func observePersonalCommittedText(
        _ text: String,
        precededBy context: String?,
        languageCode: String?
    ) {
        guard allowsPersonalLanguageLearning else { return }
        textIntelligence.observeCommittedText(
            text,
            precededBy: context,
            languageCode: languageCode
        )
    }

    func recognizeHandwriting(_ imageData: Data) async throws -> String? {
        guard delegate?.keyboardHasFullAccess == true,
              let preferences else {
            return nil
        }
        let settings = preferences.loadSettings()
        guard settings.hasAcceptedCloudProcessing else { return nil }

        let languageCode = delegate?.keyboardLanguage
            .split(separator: "-")
            .first
            .map(String.init)
        return try await handwritingClient.recognize(
            imageData: imageData,
            clientID: preferences.installationIdentifier(),
            modelID: settings.activeOpenRouterModelID,
            languageCode: languageCode
        )
    }

    func refreshSuggestions() {
        guard activePracticeSession == nil,
              delegate?.allowsAutomaticTextCorrection == true else {
            suggestions = []
            return
        }
        let context = delegate?.contextBeforeInput
        let analysis = TypingContextAnalyzer.analyze(context)
        let emojiSuggestion = emojiSuggestion(for: analysis)
        let textLimit = emojiSuggestion == nil ? 3 : 2
        var next = localTextSuggestions(for: context, limit: textLimit).map {
            keyboardSuggestion(from: $0)
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
        suggestions = Array(next.prefix(3))
    }

    private func latticeSuggestion(for context: String?) -> KeyboardSuggestion? {
        guard case .typingWord(let visibleWord) = TypingContextAnalyzer
            .analyze(context).mode,
              currentWordTaps.count == visibleWord.count else {
            return nil
        }
        let precedingContext = String((context ?? "").dropLast(visibleWord.count))
        let result = tapWordDecoder.decode(
            currentWordTaps,
            previousWord: lastWord(in: precedingContext),
            languageCode: delegate?.keyboardLanguage,
            limit: 5
        )
        guard let best = result.candidates.first,
              best.confidence >= 0.38,
              result.margin >= 0.08 else {
            return nil
        }
        let candidate = matchingCapitalization(of: best.word, to: visibleWord)
        guard candidate.caseInsensitiveCompare(visibleWord) != .orderedSame else {
            return nil
        }
        return KeyboardSuggestion(
            id: "tap-lattice-\(candidate)",
            kind: .correction,
            display: candidate,
            deleteCount: visibleWord.count,
            insertion: candidate + " "
        )
    }

    private func localTextSuggestions(
        for context: String?,
        limit: Int
    ) -> [TextSuggestion] {
        let languageCode = delegate?.keyboardLanguage
        guard case .typingWord(let partial) = TypingContextAnalyzer.analyze(context).mode else {
            return textIntelligence.suggestions(
                for: context,
                languageCode: languageCode,
                limit: limit
            )
        }

        let checkerLanguage = languageCode?
            .replacingOccurrences(of: "-", with: "_") ?? "en_US"
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

    private func keyboardSuggestion(from suggestion: TextSuggestion) -> KeyboardSuggestion {
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

        return KeyboardSuggestion(
            id: "\(idPrefix)-\(suggestion.text)",
            kind: kind,
            display: suggestion.text,
            deleteCount: suggestion.replacementLength,
            insertion: suggestion.text + " "
        )
    }

    private func emojiSuggestion(
        for analysis: TypingContextAnalysis
    ) -> KeyboardSuggestion? {
        switch analysis.mode {
        case .typingWord(let partial):
            guard let emoji = SuggestionEmojiMap.emoji(for: partial) else { return nil }
            return KeyboardSuggestion(
                id: "emoji-\(emoji)",
                kind: .emoji,
                display: emoji,
                deleteCount: partial.count,
                insertion: emoji
            )
        case .betweenWords(let lastWord):
            guard let lastWord,
                  let emoji = SuggestionEmojiMap.emoji(for: lastWord) else {
                return nil
            }
            return KeyboardSuggestion(
                id: "emoji-\(emoji)",
                kind: .emoji,
                display: emoji,
                deleteCount: lastWord.count + 1,
                insertion: emoji + " "
            )
        case .empty:
            return nil
        }
    }

    /// Corrects (when enabled) and learns the word being finished before its
    /// boundary is inserted, so both actions share the same ranking seam.
    private func commitCurrentWord() {
        let context = delegate?.contextBeforeInput
        if observedTextSuffix.consumeIfUnchanged(contextBeforeInput: context) {
            return
        }
        guard case .typingWord(let word) = TypingContextAnalyzer.analyze(context).mode else {
            return
        }
        let prefix = String((context ?? "").dropLast(word.count))
        var committedWord = word

        let settings = preferences?.loadSettings() ?? .default
        var appliedCorrection = false
        if activePracticeSession == nil,
           settings.automaticallyCorrectWords,
           delegate?.allowsAutomaticTextCorrection == true {
            if let correction = latticeCorrection(
                for: word,
                precedingContext: prefix,
                languageCode: delegate?.keyboardLanguage
            ) {
                replaceCurrentWord(word, with: correction)
                committedWord = correction
                appliedCorrection = true
            }
        }

        if activePracticeSession == nil,
           !appliedCorrection,
           settings.automaticallyCorrectWords,
           delegate?.allowsAutomaticTextCorrection == true,
           let correction = localTextSuggestions(for: context, limit: 3)
               .first(where: { $0.kind == .correction }) {
            replaceCurrentWord(word, with: correction.text)
            committedWord = correction.text
        }

        observePersonalCommittedText(
            committedWord,
            precededBy: prefix,
            languageCode: delegate?.keyboardLanguage
        )
    }

    private func latticeCorrection(
        for visibleWord: String,
        precedingContext: String,
        languageCode: String?
    ) -> String? {
        guard currentWordTaps.count == visibleWord.count else { return nil }
        let result = tapWordDecoder.decode(
            currentWordTaps,
            previousWord: lastWord(in: precedingContext),
            languageCode: languageCode,
            limit: 5
        )
        guard let best = result.candidates.first,
              best.confidence >= 0.50,
              result.margin >= 0.18 else {
            return nil
        }
        let candidate = matchingCapitalization(
            of: best.word,
            to: visibleWord
        )
        guard candidate.caseInsensitiveCompare(visibleWord) != .orderedSame else {
            return nil
        }
        return candidate
    }

    private func replaceCurrentWord(_ original: String, with replacement: String) {
        for _ in original {
            delegate?.deleteBackward()
        }
        delegate?.insertText(replacement)
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
        if let pendingCorrectionUndo,
           delegate?.canUndoCorrection(pendingCorrectionUndo) != true {
            clearCorrectionUndo()
        }
        observedTextSuffix.retainIfUnchanged(
            contextBeforeInput: delegate?.contextBeforeInput
        )
        let currentWordLength: Int
        if case .typingWord(let word) = TypingContextAnalyzer
            .analyze(delegate?.contextBeforeInput).mode {
            currentWordLength = word.count
        } else {
            currentWordLength = 0
        }
        if currentWordTaps.count != currentWordLength {
            currentWordTaps.removeAll(keepingCapacity: true)
        }
        refreshSuggestions()
        guard correctionTask != nil else { return }
        cancelCorrection()
        setQuietly(baselineStatus)
    }

    func deactivate() {
        cancelCorrection()
        clearCorrectionUndo()
        persistAdaptiveProfileIfNeeded(force: true)
        lastTypingDecision = nil
        pendingRejectedDecision = nil
        currentWordTaps.removeAll(keepingCapacity: true)
        textIntelligence.persist()
        dictationMonitorTask?.cancel()
        dictationMonitorTask = nil
        setQuietly(baselineStatus)
    }

    func toggleDictation() {
        refreshKeyboardDictationSession()

        switch dictationPhase {
        case .idle:
            beginKeyboardDictation()
        case .recording:
            requestKeyboardDictationStop()
        case .launching:
            // Allow the user to cancel a dictation that never started.
            cancelKeyboardDictation()
        case .processing:
            break
        }
    }

    func correctCurrentText() {
        cancelCorrection()
        clearCorrectionUndo()
        refreshAvailability()

        guard hasFullAccess else {
            present(.fullAccessRequired)
            return
        }

        let settings = preferences?.loadSettings() ?? .default
        guard settings.hasAcceptedCloudProcessing else {
            present(.cloudConsentRequired)
            return
        }

        guard let snapshot = delegate?.captureCorrectionSnapshot() else {
            present(.noText)
            return
        }

        guard let clientID = preferences?.installationIdentifier() else {
            present(.error("BuddyGrammar could not open its shared container."))
            return
        }

        let requestID = UUID()
        let languageCode = delegate?.keyboardLanguage
        correctionRequestID = requestID
        present(.correcting)

        correctionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let corrected = try await correctionClient.correct(
                    text: snapshot.candidate.requestText,
                    clientID: clientID,
                    modelID: settings.activeOpenRouterModelID,
                    instruction: settings.correctionInstruction
                )
                try Task.checkCancellation()
                guard correctionRequestID == requestID else { return }

                let replacement = snapshot.candidate.replacement(with: corrected)
                let appliedCorrection = delegate?.applyCorrection(replacement, to: snapshot)
                correctionTask = nil
                correctionRequestID = nil
                if let appliedCorrection {
                    observedTextSuffix.clear()
                    let learningContext: String?
                    switch snapshot.target {
                    case .selection:
                        learningContext = snapshot.contextBeforeInput
                    case .currentSentence:
                        learningContext = nil
                    }
                    beginCorrectionUndo(
                        appliedCorrection,
                        duration: settings.correctionUndoDuration,
                        learning: DeferredCorrectionLearning(
                            text: replacement,
                            precedingContext: learningContext,
                            languageCode: languageCode,
                            resultingContext: appliedCorrection.contextBeforeInput
                        )
                    )
                    present(.corrected)
                } else {
                    present(.staleContext)
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

    func undoLastCorrection() {
        guard let pendingCorrectionUndo else { return }
        clearCorrectionUndo(acceptLearning: false)
        observedTextSuffix.clear()
        let didUndo = delegate?.undoCorrection(pendingCorrectionUndo) ?? false
        present(didUndo ? .correctionUndone : .staleContext)
        refreshSuggestions()
    }

    func insertPendingTranscript() {
        cancelCorrectionForLocalEdit()
        refreshAvailability()

        guard hasFullAccess else {
            present(.fullAccessRequired)
            return
        }

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

        let context = delegate?.contextBeforeInput
        commitRecognizedText(
            transcript.text,
            context: context,
            languageCode: transcript.languageCode
        )
        preferences.clearPendingTranscript()
        hasPendingTranscript = false
        present(.transcriptInserted)
        refreshSuggestions()
    }

    private func capitalized(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first).uppercased() + word.dropFirst()
    }

    private func beginKeyboardDictation() {
        refreshAvailability()
        guard hasFullAccess else {
            present(.fullAccessRequired)
            return
        }
        guard let preferences else {
            present(.error("BuddyGrammar could not open its shared container."))
            return
        }
        let settings = preferences.loadSettings()
        guard settings.hasAcceptedCloudProcessing else {
            present(.cloudConsentRequired)
            return
        }

        do {
            let session = try preferences.beginKeyboardDictationSession()
            if preferences.isCompanionAlive() {
                keyboardDictationLog.notice("Signaling Dynamic Island dictation session \(session.id, privacy: .public)")
                updateDictationPhase(.launching, status: .startingDictation)
                DictationCompanionNotifier.post(.startRequested)
                scheduleDictationHandoffFallback(sessionID: session.id)
            } else {
                keyboardDictationLog.notice("Opening BuddyGrammar for dictation session \(session.id, privacy: .public)")
                updateDictationPhase(.launching, status: .openingDictation)
                openDictationDeepLink(sessionID: session.id)
            }
        } catch {
            keyboardDictationLog.error("Failed to begin dictation session: \(error, privacy: .public)")
            present(.error("BuddyGrammar could not start voice dictation."))
        }
    }

    private func scheduleDictationHandoffFallback(sessionID: UUID) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled,
                  let self,
                  let session = preferences?.loadKeyboardDictationSession(),
                  session.id == sessionID,
                  session.phase == .launching else { return }
            keyboardDictationLog.warning("Dynamic Island did not answer; opening BuddyGrammar")
            updateDictationPhase(.launching, status: .openingDictation)
            openDictationDeepLink(sessionID: sessionID)
        }
    }

    private func openDictationDeepLink(sessionID: UUID) {
        guard let url = KeyboardDictationHandoff.url(for: sessionID),
              let delegate else {
            failDictationHandoff(sessionID: sessionID)
            return
        }
        delegate.openHostApplication(url) { [weak self] didOpen in
            guard let self, !didOpen,
                  let session = preferences?.loadKeyboardDictationSession(),
                  session.id == sessionID,
                  session.phase == .launching else {
                return
            }
            keyboardDictationLog.error("iOS rejected the BuddyGrammar dictation handoff")
            failDictationHandoff(sessionID: sessionID)
        }
    }

    private func failDictationHandoff(sessionID: UUID) {
        preferences?.clearKeyboardDictationSession(id: sessionID)
        dictationPhase = .idle
        present(.error("Open BuddyGrammar once, then try the microphone again."))
    }

    private func cancelKeyboardDictation() {
        keyboardDictationLog.notice("User canceled launching dictation")
        if let session = preferences?.loadKeyboardDictationSession() {
            preferences?.clearKeyboardDictationSession(id: session.id)
        }
        dictationPhase = .idle
        present(baselineStatus)
    }

    private func requestKeyboardDictationStop() {
        guard let preferences,
              let session = preferences.loadKeyboardDictationSession() else {
            updateDictationPhase(.idle, status: baselineStatus)
            return
        }
        do {
            guard try preferences.requestKeyboardDictationStop(id: session.id) != nil else {
                refreshKeyboardDictationSession()
                return
            }
            DictationCompanionNotifier.post(.stopRequested)
            updateDictationPhase(.processing, status: .dictationProcessing)
        } catch {
            present(.error("BuddyGrammar could not stop voice dictation."))
        }
    }

    private func startDictationMonitor() {
        dictationMonitorTask?.cancel()
        dictationMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshKeyboardDictationSession()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func refreshKeyboardDictationSession() {
        guard let preferences,
              let session = preferences.loadKeyboardDictationSession() else {
            if dictationPhase != .idle {
                dictationPhase = .idle
            }
            return
        }

        switch session.phase {
        case .launching:
            // A session stuck in launching means the app never picked it
            // up (or was closed); expire it so the mic button recovers.
            if Date.now.timeIntervalSince(session.updatedAt) > 15 {
                keyboardDictationLog.warning("Expiring stale launching session \(session.id, privacy: .public)")
                preferences.clearKeyboardDictationSession(id: session.id)
                dictationPhase = .idle
                present(.error("Voice dictation didn’t start. Try again."))
                return
            }
            updateDictationPhase(.launching, status: .openingDictation)
        case .recording:
            updateDictationPhase(.recording, status: .dictationRecording)
        case .stopRequested, .transcribing:
            updateDictationPhase(.processing, status: .dictationProcessing)
        case .ready:
            guard let transcript = session.transcript?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !transcript.isEmpty else {
                preferences.clearKeyboardDictationSession(id: session.id)
                dictationPhase = .idle
                present(.error("Voice dictation returned no text."))
                return
            }
            preferences.clearKeyboardDictationSession(id: session.id)
            preferences.clearPendingTranscript()
            hasPendingTranscript = false
            dictationPhase = .idle
            insertDictatedText(transcript, languageCode: session.languageCode)
            present(.transcriptInserted)
        case .failed:
            preferences.clearKeyboardDictationSession(id: session.id)
            dictationPhase = .idle
            present(.error(session.errorMessage ?? "Voice dictation failed."))
        }
    }

    private func updateDictationPhase(
        _ phase: KeyboardDictationPhase,
        status: KeyboardStatus
    ) {
        guard dictationPhase != phase else { return }
        dictationPhase = phase
        present(status)
    }

    private func refreshPendingTranscriptAvailability() {
        hasPendingTranscript = preferences?.loadPendingTranscript().map {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
    }

    private func beginCorrectionUndo(
        _ correction: AppliedCorrection,
        duration: TimeInterval,
        learning: DeferredCorrectionLearning
    ) {
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
        deferredCorrectionLearning = nil
        pendingCorrectionUndo = nil
        canUndoCorrection = false

        guard acceptLearning, let learning else { return }
        observePersonalCommittedText(
            learning.text,
            precededBy: learning.precedingContext,
            languageCode: learning.languageCode
        )
        if delegate?.contextBeforeInput == learning.resultingContext {
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

    private func availabilityStatus() -> KeyboardStatus {
        let fullAccess = delegate?.keyboardHasFullAccess ?? false
        hasFullAccess = fullAccess
        guard fullAccess else { return .fullAccessRequired }

        let settings = preferences?.loadSettings() ?? .default
        guard settings.hasAcceptedCloudProcessing else {
            return .cloudConsentRequired
        }

        return .ready
    }

    private static let autocorrectionBoundaryCharacters: Set<String> = [
        ".", ",", "?", "!", ";", ":",
    ]
}
