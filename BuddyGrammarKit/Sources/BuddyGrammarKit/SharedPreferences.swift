import Foundation

public final class SharedPreferences: @unchecked Sendable {
    private enum Key {
        static let settings = "BuddyGrammar.iOS.settings"
        static let pendingTranscript = "BuddyGrammar.iOS.pendingTranscript"
        static let installationIdentifier = "BuddyGrammar.iOS.installationIdentifier"
    }

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

    public func installationIdentifier() -> UUID {
        if let storedValue = defaults.string(forKey: Key.installationIdentifier),
           let identifier = UUID(uuidString: storedValue) {
            return identifier
        }

        let identifier = UUID()
        defaults.set(identifier.uuidString, forKey: Key.installationIdentifier)
        return identifier
    }

    private func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, forKey key: String) throws {
        defaults.set(try encoder.encode(value), forKey: key)
    }
}
