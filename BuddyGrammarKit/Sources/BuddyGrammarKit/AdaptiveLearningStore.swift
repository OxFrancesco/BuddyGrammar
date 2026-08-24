import Foundation

public enum AdaptiveLearningScope: String, CaseIterable, Sendable {
    case typing
    case language
    case practice
    case all
}

/// The only cross-process practice context visible to the keyboard. The
/// expected text comes from BuddyGrammar's curated prompt bank; no user-authored
/// response or touch trajectory is stored here.
public struct ActivePracticeSession: Codable, Equatable, Sendable {
    public static let maximumExpectedCharacterCount = 512

    public let id: UUID
    public let promptID: String
    public let expectedText: String
    public let languageCode: String?
    public let startedAt: Date

    public init(
        id: UUID = UUID(),
        promptID: String,
        expectedText: String,
        languageCode: String? = nil,
        startedAt: Date = .now
    ) {
        self.id = id
        self.promptID = String(promptID.prefix(128))
        self.expectedText = String(
            expectedText.prefix(Self.maximumExpectedCharacterCount)
        )
        self.languageCode = languageCode.map { String($0.prefix(32)) }
        self.startedAt = startedAt
    }
}

/// Versioned, aggregate-only persistence shared by the containing app and its
/// keyboard extension. Independent keys avoid lost updates between the two
/// processes and make each learning family separately resettable.
public final class AdaptiveLearningStore: @unchecked Sendable {
    public static let practiceSessionLifetime: TimeInterval = 30 * 60

    private enum Key {
        static let typingProfile = "BuddyGrammar.adaptive.typing.v1"
        static let practiceProfile = "BuddyGrammar.adaptive.practice.v1"
        static let activePracticeSession = "BuddyGrammar.adaptive.session.v1"
    }

    private struct VersionedTypingProfile: Codable {
        let resetGeneration: UInt64
        let profile: TypingProfile
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    public convenience init?() {
        guard let defaults = UserDefaults(
            suiteName: BuddyGrammarConfiguration.appGroupIdentifier
        ) else {
            return nil
        }
        self.init(defaults: defaults)
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func loadTypingProfile() -> TypingProfile {
        withLock {
            guard let data = defaults.data(forKey: Key.typingProfile) else {
                return TypingProfile()
            }
            let generation = SharedPreferences(defaults: defaults)
                .loadLearningResetGenerations().typing
            if let versioned = try? decoder.decode(
                VersionedTypingProfile.self,
                from: data
            ) {
                guard versioned.resetGeneration == generation else {
                    defaults.removeObject(forKey: Key.typingProfile)
                    return TypingProfile()
                }
                return versioned.profile
            }
            // Generation zero is the only epoch that may contain the legacy
            // unwrapped profile. After any reset, a legacy write is stale.
            if generation == 0,
               let legacy = try? decoder.decode(TypingProfile.self, from: data) {
                return legacy
            }
            defaults.removeObject(forKey: Key.typingProfile)
            return TypingProfile()
        }
    }

    @discardableResult
    public func saveTypingProfile(
        _ profile: TypingProfile,
        expectedResetGeneration: UInt64? = nil
    ) throws -> Bool {
        try withLock {
            let preferences = SharedPreferences(defaults: defaults)
            let generation = preferences.loadLearningResetGenerations().typing
            guard expectedResetGeneration == nil
                    || expectedResetGeneration == generation else {
                return false
            }
            defaults.set(
                try encoder.encode(
                    VersionedTypingProfile(
                        resetGeneration: generation,
                        profile: profile
                    )
                ),
                forKey: Key.typingProfile
            )
            return preferences.loadLearningResetGenerations().typing == generation
        }
    }

    public func loadPracticeProfile() -> PracticeProfile {
        load(PracticeProfile.self, forKey: Key.practiceProfile) ?? PracticeProfile()
    }

    public func savePracticeProfile(_ profile: PracticeProfile) throws {
        try save(profile, forKey: Key.practiceProfile)
    }

    public func loadActivePracticeSession(
        now: Date = .now
    ) -> ActivePracticeSession? {
        guard let session = load(
            ActivePracticeSession.self,
            forKey: Key.activePracticeSession
        ) else {
            return nil
        }
        let age = now.timeIntervalSince(session.startedAt)
        guard age >= -60, age <= Self.practiceSessionLifetime else {
            clearActivePracticeSession(id: session.id)
            return nil
        }
        return session
    }

    public func saveActivePracticeSession(
        _ session: ActivePracticeSession
    ) throws {
        try save(session, forKey: Key.activePracticeSession)
    }

    public func clearActivePracticeSession(id: UUID? = nil) {
        withLock {
            if let id,
               let data = defaults.data(forKey: Key.activePracticeSession),
               let session = try? decoder.decode(
                   ActivePracticeSession.self,
                   from: data
               ),
               session.id != id {
                return
            }
            defaults.removeObject(forKey: Key.activePracticeSession)
        }
    }

    public func reset(_ scope: AdaptiveLearningScope) {
        withLock {
            switch scope {
            case .typing:
                SharedPreferences(defaults: defaults)
                    .advanceTypingLearningResetGeneration()
                defaults.removeObject(forKey: Key.typingProfile)
            case .language:
                break
            case .practice:
                defaults.removeObject(forKey: Key.practiceProfile)
                defaults.removeObject(forKey: Key.activePracticeSession)
            case .all:
                SharedPreferences(defaults: defaults)
                    .advanceTypingLearningResetGeneration()
                defaults.removeObject(forKey: Key.typingProfile)
                defaults.removeObject(forKey: Key.practiceProfile)
                defaults.removeObject(forKey: Key.activePracticeSession)
            }
        }
    }

    private func load<Value: Decodable>(
        _ type: Value.Type,
        forKey key: String
    ) -> Value? {
        withLock {
            guard let data = defaults.data(forKey: key) else { return nil }
            guard let value = try? decoder.decode(type, from: data) else {
                defaults.removeObject(forKey: key)
                return nil
            }
            return value
        }
    }

    private func save<Value: Encodable>(
        _ value: Value,
        forKey key: String
    ) throws {
        try withLock {
            defaults.set(try encoder.encode(value), forKey: key)
        }
    }

    private func withLock<Value>(_ operation: () throws -> Value) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
