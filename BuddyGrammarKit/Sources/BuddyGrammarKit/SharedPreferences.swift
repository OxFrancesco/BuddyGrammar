import Foundation

public struct LearningResetGenerations: Equatable, Sendable {
    public let language: UInt64
    public let typing: UInt64

    public init(language: UInt64 = 0, typing: UInt64 = 0) {
        self.language = language
        self.typing = typing
    }
}

public final class SharedPreferences: @unchecked Sendable {
    private enum Key {
        static let settings = "BuddyGrammar.iOS.settings"
        static let pendingTranscript = "BuddyGrammar.iOS.pendingTranscript"
        static let savedDictation = "BuddyGrammar.iOS.savedDictation"
        static let keyboardDictationSession = "BuddyGrammar.iOS.keyboardDictationSession"
        static let dictationHandoffRequest = "BuddyGrammar.iOS.dictationHandoffRequest"
        static let installationIdentifier = "BuddyGrammar.iOS.installationIdentifier"
        static let companionHeartbeat = "BuddyGrammar.iOS.companionHeartbeat"
        static let languageLearningResetGeneration =
            "BuddyGrammar.iOS.learningReset.language.v1"
        static let typingLearningResetGeneration =
            "BuddyGrammar.iOS.learningReset.typing.v1"
    }

    private static let resetGenerationLock = NSLock()

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public convenience init?() {
        guard let defaults = UserDefaults(suiteName: BuddyGrammarConfiguration.appGroupIdentifier) else {
            return nil
        }
        self.init(defaults: defaults)
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func loadSettings() -> BuddyGrammarSettings {
        load(BuddyGrammarSettings.self, forKey: Key.settings) ?? .default
    }

    public func saveSettings(_ settings: BuddyGrammarSettings) throws {
        try save(settings, forKey: Key.settings)
    }

    public func loadPendingTranscript(now: Date = .now) -> PendingTranscript? {
        guard let transcript = load(PendingTranscript.self, forKey: Key.pendingTranscript) else {
            return nil
        }

        guard now.timeIntervalSince(transcript.createdAt)
            <= BuddyGrammarConfiguration.pendingTranscriptLifetime else {
            clearPendingTranscript()
            return nil
        }

        return transcript
    }

    public func savePendingTranscript(_ transcript: PendingTranscript) throws {
        try save(transcript, forKey: Key.pendingTranscript)
    }

    public func clearPendingTranscript() {
        defaults.removeObject(forKey: Key.pendingTranscript)
    }

    public func loadSavedDictation() -> SavedDictation? {
        load(SavedDictation.self, forKey: Key.savedDictation)
    }

    public func saveDictation(_ dictation: SavedDictation) throws {
        try save(dictation, forKey: Key.savedDictation)
    }

    public func clearSavedDictation() {
        defaults.removeObject(forKey: Key.savedDictation)
    }

    /// Pending keyboard→app dictation handoff. The keyboard records a request
    /// before opening the app; the app consumes it the moment the deep link
    /// arrives, so an unconsumed request means the launch never happened.
    public func saveDictationHandoffRequest(_ date: Date) {
        try? save(date, forKey: Key.dictationHandoffRequest)
    }

    public func consumeDictationHandoffRequest() -> Bool {
        let existed = defaults.object(forKey: Key.dictationHandoffRequest) != nil
        defaults.removeObject(forKey: Key.dictationHandoffRequest)
        return existed
    }

    @discardableResult
    public func beginKeyboardDictationSession(
        id: UUID = UUID(),
        now: Date = .now
    ) throws -> KeyboardDictationSession {
        let session = KeyboardDictationSession(
            id: id,
            createdAt: now,
            updatedAt: now,
            phase: .launching
        )
        try save(session, forKey: Key.keyboardDictationSession)
        return session
    }

    public func loadKeyboardDictationSession(
        now: Date = .now
    ) -> KeyboardDictationSession? {
        guard let session = load(
            KeyboardDictationSession.self,
            forKey: Key.keyboardDictationSession
        ) else {
            return nil
        }
        guard now.timeIntervalSince(session.updatedAt)
            <= BuddyGrammarConfiguration.keyboardDictationSessionLifetime else {
            clearKeyboardDictationSession(id: session.id)
            return nil
        }
        return session
    }

    @discardableResult
    public func updateKeyboardDictationSession(
        id: UUID,
        phase: KeyboardDictationSession.Phase,
        transcript: String? = nil,
        languageCode: String? = nil,
        errorMessage: String? = nil,
        now: Date = .now
    ) throws -> KeyboardDictationSession? {
        guard let session = loadKeyboardDictationSession(now: now),
              session.id == id else {
            return nil
        }
        let updated = session.updating(
            phase: phase,
            transcript: transcript,
            languageCode: languageCode,
            errorMessage: errorMessage,
            at: now
        )
        try save(updated, forKey: Key.keyboardDictationSession)
        return updated
    }

    @discardableResult
    public func requestKeyboardDictationStop(
        id: UUID,
        now: Date = .now
    ) throws -> KeyboardDictationSession? {
        guard let session = loadKeyboardDictationSession(now: now),
              session.id == id,
              session.phase == .recording else {
            return nil
        }
        return try updateKeyboardDictationSession(
            id: id,
            phase: .stopRequested,
            now: now
        )
    }

    public func clearKeyboardDictationSession(id: UUID? = nil) {
        if let id,
           let session = load(
               KeyboardDictationSession.self,
               forKey: Key.keyboardDictationSession
           ),
           session.id != id {
            return
        }
        defaults.removeObject(forKey: Key.keyboardDictationSession)
    }

    public func recordCompanionHeartbeat(now: Date = .now) {
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: Key.companionHeartbeat)
    }

    public func clearCompanionHeartbeat() {
        defaults.removeObject(forKey: Key.companionHeartbeat)
    }

    public func isCompanionAlive(
        now: Date = .now,
        tolerance: TimeInterval = BuddyGrammarConfiguration.companionHeartbeatTolerance
    ) -> Bool {
        let storedValue = defaults.double(forKey: Key.companionHeartbeat)
        guard storedValue > 0 else { return false }
        let heartbeat = Date(timeIntervalSinceReferenceDate: storedValue)
        let age = now.timeIntervalSince(heartbeat)
        return age >= -tolerance && age <= tolerance
    }

    public func installationIdentifier() -> UUID {
        if let storedValue = defaults.string(forKey: Key.installationIdentifier),
           let identifier = UUID(uuidString: storedValue) {
            return identifier
        }

        let identifier = UUID()
        defaults.set(identifier.uuidString, forKey: Key.installationIdentifier)
        return identifier
    }

    public func loadLearningResetGenerations() -> LearningResetGenerations {
        LearningResetGenerations(
            language: Self.loadResetGeneration(
                from: defaults,
                forKey: Key.languageLearningResetGeneration
            ),
            typing: Self.loadResetGeneration(
                from: defaults,
                forKey: Key.typingLearningResetGeneration
            )
        )
    }

    @discardableResult
    public func advanceLanguageLearningResetGeneration() -> UInt64 {
        advanceResetGeneration(forKey: Key.languageLearningResetGeneration)
    }

    @discardableResult
    public func advanceTypingLearningResetGeneration() -> UInt64 {
        advanceResetGeneration(forKey: Key.typingLearningResetGeneration)
    }

    /// Creates the language model against the same App Group suite and reset
    /// generation as these preferences. Callers without shared preferences
    /// should construct an in-memory-only model with `defaults: nil` instead.
    public func makePersonalLanguageModel() -> PersonalLanguageModel {
        let defaults = defaults
        return PersonalLanguageModel(
            defaults: defaults,
            resetGeneration: {
                Self.loadResetGeneration(
                    from: defaults,
                    forKey: Key.languageLearningResetGeneration
                )
            }
        )
    }

    /// Advances the epoch before deleting the durable model. A live keyboard
    /// therefore rejects stale in-memory writes even if reset and persistence
    /// overlap across the containing app and extension processes.
    public func resetPersonalLanguageLearning() {
        advanceLanguageLearningResetGeneration()
        makePersonalLanguageModel().reset()
    }

    private func advanceResetGeneration(forKey key: String) -> UInt64 {
        Self.resetGenerationLock.lock()
        defer { Self.resetGenerationLock.unlock() }
        let current = Self.loadResetGeneration(from: defaults, forKey: key)
        let next = current == .max ? 1 : current + 1
        defaults.set(NSNumber(value: next), forKey: key)
        return next
    }

    private static func loadResetGeneration(
        from defaults: UserDefaults,
        forKey key: String
    ) -> UInt64 {
        (defaults.object(forKey: key) as? NSNumber)?.uint64Value ?? 0
    }

    private func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, forKey key: String) throws {
        defaults.set(try encoder.encode(value), forKey: key)
    }
}
