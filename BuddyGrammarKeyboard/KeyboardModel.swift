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
    case openingDictation
    case startingDictation
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
        case .openingDictation:
            "Opening voice dictation…"
        case .startingDictation:
            "Starting dictation… Speak when the mic turns on."
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
             .transcriptInserted, .openingDictation, .startingDictation,
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
    case wholeText(charactersAfterCursor: Int)
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

    func insertText(_ text: String)
    func deleteBackward()
    func captureCorrectionSnapshot() -> DocumentCorrectionSnapshot?
    func applyCorrection(
        _ replacement: String,
        to snapshot: DocumentCorrectionSnapshot
    ) -> AppliedCorrection?
    func canUndoCorrection(_ correction: AppliedCorrection) -> Bool
    func undoCorrection(_ correction: AppliedCorrection) -> Bool
    func openHostApplication(_ url: URL) -> Bool
}

@MainActor
struct WordCompletionSource {
    private let checker = UITextChecker()

    func completions(for partial: String, language: String = "en_US") -> [String] {
        let range = NSRange(location: 0, length: (partial as NSString).length)
        if let completions = checker.completions(forPartialWordRange: range, in: partial, language: language),
           !completions.isEmpty {
            return completions
        }
        return checker.guesses(forWordRange: range, in: partial, language: language) ?? []
    }

    func correction(
        for word: String,
        language: String,
        supplementalReplacements: [String: String]
    ) -> String? {
        if let replacement = supplementalReplacements[word.lowercased()],
           replacement.caseInsensitiveCompare(word) != .orderedSame {
            return replacement
        }

        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelledRange = checker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: language
        )
        guard misspelledRange.location != NSNotFound,
              misspelledRange.length == range.length else {
            return nil
        }
        let guesses = checker.guesses(
            forWordRange: range,
            in: word,
            language: language
        ) ?? []
        return LocalWordCorrector.bestCorrection(for: word, candidates: guesses)
    }
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

    @ObservationIgnored private weak var delegate: KeyboardModelDelegate?
    @ObservationIgnored private let correctionClient: OpenRouterCorrectionClient
    @ObservationIgnored private let handwritingClient: HandwritingRecognitionClient
    @ObservationIgnored private let preferences: SharedPreferences?
    @ObservationIgnored private let completionSource = WordCompletionSource()
    @ObservationIgnored private var correctionTask: Task<Void, Never>?
    @ObservationIgnored private var correctionRequestID: UUID?
    @ObservationIgnored private var statusDismissTask: Task<Void, Never>?
    @ObservationIgnored private var undoDismissTask: Task<Void, Never>?
    @ObservationIgnored private var dictationMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var companionFallbackTask: Task<Void, Never>?
    @ObservationIgnored private var baselineStatus: KeyboardStatus = .fullAccessRequired
    @ObservationIgnored private var pendingCorrectionUndo: AppliedCorrection?
    @ObservationIgnored private var supplementalReplacements: [String: String] = [:]
    @ObservationIgnored private var cachedSwipeEngine: SwipeTypingEngine?
    @ObservationIgnored private var didWarmUpConnection = false
    @ObservationIgnored private let personalModel = PersonalLanguageModel()

    init(
        correctionClient: OpenRouterCorrectionClient = OpenRouterCorrectionClient(),
        handwritingClient: HandwritingRecognitionClient = HandwritingRecognitionClient(),
        preferences: SharedPreferences? = SharedPreferences()
    ) {
        self.correctionClient = correctionClient
        self.handwritingClient = handwritingClient
        self.preferences = preferences
    }

    func connect(delegate: KeyboardModelDelegate) {
        self.delegate = delegate
        activate()
    }

    func activate() {
        refreshAvailability()
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
        cancelCorrectionForLocalEdit()
        if Self.autocorrectionBoundaryCharacters.contains(character) {
            applyLocalWordCorrectionIfNeeded()
            learnCompletedWord()
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

    func insertSpace() {
        cancelCorrectionForLocalEdit()
        applyLocalWordCorrectionIfNeeded()
        learnCompletedWord()
        delegate?.insertText(" ")
        refreshSuggestions()
    }

    func insertReturn() {
        cancelCorrectionForLocalEdit()
        applyLocalWordCorrectionIfNeeded()
        learnCompletedWord()
        delegate?.insertText("\n")
        if layoutMode == .letters, shiftState == .lowercase {
            shiftState = .uppercase
        }
        refreshSuggestions()
    }

    func deleteBackward() {
        cancelCorrectionForLocalEdit()
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
        if suggestion.kind != .emoji {
            let context = delegate?.contextBeforeInput ?? ""
            let prefix = String(context.dropLast(suggestion.deleteCount))
            personalModel.learn(
                previousWord: lastWord(in: prefix),
                word: suggestion.insertion.trimmingCharacters(in: .whitespaces)
            )
        }
        for _ in 0..<suggestion.deleteCount {
            delegate?.deleteBackward()
        }
        delegate?.insertText(suggestion.insertion)
        if layoutMode == .letters, shiftState == .uppercase {
            shiftState = .lowercase
        }
        refreshSuggestions()
    }

    func insertEmoji(_ emoji: String) {
        cancelCorrectionForLocalEdit()
        delegate?.insertText(emoji)
        refreshSuggestions()
    }

    func insertRecognizedText(_ text: String) {
        cancelCorrectionForLocalEdit()
        let context = delegate?.contextBeforeInput
        let formatted = HandwritingTextFormatter.textForInsertion(
            text,
            contextBeforeInput: context
        )
        insertTextRespectingContext(formatted, context: context)
        refreshSuggestions()
    }

    private func insertDictatedText(_ text: String) {
        cancelCorrectionForLocalEdit()
        let context = delegate?.contextBeforeInput
        insertTextRespectingContext(text, context: context)
        refreshSuggestions()
    }

    private func insertTextRespectingContext(_ text: String, context: String?) {
        let needsLeadingSpace = context?.last.map { !$0.isWhitespace } ?? false
        delegate?.insertText(needsLeadingSpace ? " \(text)" : text)
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
        let word = applyingShift(to: best)
        insertTextRespectingContext(word, context: context)
        if shiftState == .uppercase {
            shiftState = .lowercase
        }

        // Offer the runner-up words as one-tap replacements.
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
        let analysis = TypingContextAnalyzer.analyze(delegate?.contextBeforeInput)
        var next: [KeyboardSuggestion] = []

        switch analysis.mode {
        case .typingWord(let partial):
            let completions = rankedCompletions(for: partial, limit: 2)
            next = completions.map { word in
                KeyboardSuggestion(
                    id: "completion-\(word)",
                    kind: .completion,
                    display: word,
                    deleteCount: partial.count,
                    insertion: word + " "
                )
            }
            if let emoji = SuggestionEmojiMap.emoji(for: partial) {
                next.append(
                    KeyboardSuggestion(
                        id: "emoji-\(emoji)",
                        kind: .emoji,
                        display: emoji,
                        deleteCount: partial.count,
                        insertion: emoji
                    )
                )
            }
        case .betweenWords(let lastWord):
            next = NextWordPredictor.predictions(
                after: lastWord,
                personal: personalModel,
                limit: 2
            ).map { word in
                let display = analysis.isAtSentenceStart ? capitalized(word) : word
                return KeyboardSuggestion(
                    id: "prediction-\(display)",
                    kind: .prediction,
                    display: display,
                    deleteCount: 0,
                    insertion: display + " "
                )
            }
            if let lastWord, let emoji = SuggestionEmojiMap.emoji(for: lastWord) {
                next.append(
                    KeyboardSuggestion(
                        id: "emoji-\(emoji)",
                        kind: .emoji,
                        display: emoji,
                        deleteCount: lastWord.count + 1,
                        insertion: emoji + " "
                    )
                )
            }
        case .empty:
            next = NextWordPredictor.predictions(after: nil, limit: 2).map { word in
                let display = capitalized(word)
                return KeyboardSuggestion(
                    id: "prediction-\(display)",
                    kind: .prediction,
                    display: display,
                    deleteCount: 0,
                    insertion: display + " "
                )
            }
        }

        suggestions = Array(next.prefix(3))
    }

    /// Completions ranked by how likely the user actually wants them: their
    /// own frequent words first, then common English words by corpus
    /// frequency, with UITextChecker's (alphabetical) list as a fallback.
    private func rankedCompletions(for partial: String, limit: Int) -> [String] {
        var ranked: [String] = []
        func append(_ candidates: [String]) {
            for candidate in candidates
            where candidate.caseInsensitiveCompare(partial) != .orderedSame
                && !ranked.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                ranked.append(candidate)
                if ranked.count == limit { return }
            }
        }
        append(personalModel.completions(forPrefix: partial, limit: limit))
        if ranked.count < limit {
            append(WordFrequencyLexicon.shared.completions(forPrefix: partial, limit: limit + 1))
        }
        if ranked.count < limit {
            let language = delegate?.keyboardLanguage
                .replacingOccurrences(of: "-", with: "_") ?? "en_US"
            append(completionSource.completions(for: partial, language: language))
        }
        return ranked.map { matchingCase($0, toTyped: partial) }
    }

    private func matchingCase(_ word: String, toTyped typed: String) -> String {
        if word == "I" { return word }
        if typed.count > 1,
           typed.contains(where: \.isLetter),
           typed.allSatisfy({ !$0.isLetter || $0.isUppercase }) {
            return word.uppercased()
        }
        if typed.first?.isUppercase == true {
            return capitalized(word)
        }
        return word
    }

    /// Records the word being finished (before a space, return, or
    /// punctuation) so predictions adapt to the user's vocabulary.
    private func learnCompletedWord() {
        let context = delegate?.contextBeforeInput
        guard case .typingWord(let word) = TypingContextAnalyzer.analyze(context).mode else {
            return
        }
        let prefix = String((context ?? "").dropLast(word.count))
        personalModel.learn(previousWord: lastWord(in: prefix), word: word)
    }

    func documentContextDidChange() {
        refreshSuggestions()
        if let pendingCorrectionUndo,
           delegate?.canUndoCorrection(pendingCorrectionUndo) != true {
            clearCorrectionUndo()
        }
        guard correctionTask != nil else { return }
        cancelCorrection()
        setQuietly(baselineStatus)
    }

    func deactivate() {
        personalModel.persist()
        cancelCorrection()
        clearCorrectionUndo()
        dictationMonitorTask?.cancel()
        dictationMonitorTask = nil
        companionFallbackTask?.cancel()
        companionFallbackTask = nil
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
                    beginCorrectionUndo(
                        appliedCorrection,
                        duration: settings.correctionUndoDuration
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
        let didUndo = delegate?.undoCorrection(pendingCorrectionUndo) ?? false
        clearCorrectionUndo()
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
            present(.noPendingTranscript)
            return
        }

        delegate?.insertText(transcript.text)
        preferences.clearPendingTranscript()
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
                // The companion (main app kept alive by Picture in Picture)
                // can start the microphone without leaving this app.
                keyboardDictationLog.notice("Companion alive; posting start signal for session \(session.id, privacy: .public)")
                DictationCompanionNotifier.post(.startRequested)
                updateDictationPhase(.launching, status: .startingDictation)
                scheduleCompanionFallback(sessionID: session.id)
                return
            }
            keyboardDictationLog.notice("Companion not alive; deep linking for session \(session.id, privacy: .public)")
            guard openDictationDeepLink(sessionID: session.id) else {
                preferences.clearKeyboardDictationSession(id: session.id)
                present(.error("Open BuddyGrammar to dictate."))
                return
            }
            updateDictationPhase(.launching, status: .openingDictation)
        } catch {
            keyboardDictationLog.error("Failed to begin dictation session: \(error, privacy: .public)")
            present(.error("BuddyGrammar could not start voice dictation."))
        }
    }

    private func openDictationDeepLink(sessionID: UUID) -> Bool {
        var components = URLComponents()
        components.scheme = "buddygrammar"
        components.host = "dictation"
        components.queryItems = [
            URLQueryItem(name: "source", value: "keyboard"),
            URLQueryItem(name: "session", value: sessionID.uuidString),
        ]
        guard let url = components.url else { return false }
        return delegate?.openHostApplication(url) == true
    }

    private func scheduleCompanionFallback(sessionID: UUID) {
        companionFallbackTask?.cancel()
        companionFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            guard let session = preferences?.loadKeyboardDictationSession(),
                  session.id == sessionID,
                  session.phase == .launching else { return }
            // The companion never picked up the request; fall back to
            // opening the app the classic way.
            keyboardDictationLog.warning("Companion did not pick up session \(sessionID, privacy: .public); falling back to deep link")
            if openDictationDeepLink(sessionID: sessionID) {
                present(.openingDictation)
            } else {
                preferences?.clearKeyboardDictationSession(id: sessionID)
                dictationPhase = .idle
                present(.error("Open BuddyGrammar to dictate."))
            }
        }
    }

    private func cancelKeyboardDictation() {
        keyboardDictationLog.notice("User canceled launching dictation")
        companionFallbackTask?.cancel()
        companionFallbackTask = nil
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

        if session.phase != .launching {
            companionFallbackTask?.cancel()
            companionFallbackTask = nil
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
            dictationPhase = .idle
            insertDictatedText(transcript)
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

    private func applyLocalWordCorrectionIfNeeded() {
        let settings = preferences?.loadSettings() ?? .default
        guard settings.automaticallyCorrectWords,
              case .typingWord(let word) = TypingContextAnalyzer
                .analyze(delegate?.contextBeforeInput)
                .mode else {
            return
        }

        let language = delegate?.keyboardLanguage.replacingOccurrences(of: "-", with: "_")
            ?? "en_US"
        guard let replacement = completionSource.correction(
            for: word,
            language: language,
            supplementalReplacements: supplementalReplacements
        ) else {
            return
        }

        for _ in word {
            delegate?.deleteBackward()
        }
        delegate?.insertText(replacement)
    }

    private func beginCorrectionUndo(
        _ correction: AppliedCorrection,
        duration: TimeInterval
    ) {
        pendingCorrectionUndo = correction
        canUndoCorrection = true
        undoDismissTask?.cancel()
        undoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.clearCorrectionUndo()
        }
    }

    private func clearCorrectionUndo() {
        undoDismissTask?.cancel()
        undoDismissTask = nil
        pendingCorrectionUndo = nil
        canUndoCorrection = false
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
