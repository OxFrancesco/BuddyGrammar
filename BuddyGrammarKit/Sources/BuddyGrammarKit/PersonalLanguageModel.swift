import Foundation

/// Learns the user's own unigram and bigram frequencies from what they type
/// so predictions and completions adapt to their vocabulary over time.
///
/// Counts are stored in the provided `UserDefaults` (the keyboard extension's
/// own container, so nothing leaves the device) and capped with periodic
/// halving so old habits decay instead of dominating forever.
public final class PersonalLanguageModel {
    private struct Storage: Codable {
        var unigrams: [String: Int] = [:]
        var bigrams: [String: [String: Int]] = [:]
    }

    private static let storageKey = "personalLanguageModel.v1"
    private static let maximumUnigrams = 3_000
    private static let maximumBigramContexts = 1_500
    private static let maximumContinuationsPerContext = 6
    private static let saveInterval = 20
    private static let maximumWordLength = 24

    private var storage: Storage
    private let defaults: UserDefaults?
    private var unsavedChanges = 0

    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Storage.self, from: data) {
            storage = decoded
        } else {
            storage = Storage()
        }
    }

    // MARK: - Learning

    public func learn(previousWord: String?, word: String) {
        guard let word = Self.normalized(word) else { return }
        storage.unigrams[word, default: 0] += 1
        if let previous = previousWord.flatMap(Self.normalized) {
            storage.bigrams[previous, default: [:]][word, default: 0] += 1
        }
        enforceLimits()
        unsavedChanges += 1
        if unsavedChanges >= Self.saveInterval {
            persist()
        }
    }

    // MARK: - Predictions

    /// Next words the user has typed after `previousWord`, most frequent first.
    public func predictions(after previousWord: String?, limit: Int) -> [String] {
        guard limit > 0,
              let previous = previousWord.flatMap(Self.normalized),
              let continuations = storage.bigrams[previous] else {
            return []
        }
        return continuations
            .filter { $0.value >= 2 }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit)
            .map(\.key)
    }

    /// The user's own words starting with `prefix`, most used first.
    public func completions(forPrefix prefix: String, limit: Int) -> [String] {
        guard limit > 0, let normalized = Self.normalized(prefix) else { return [] }
        return storage.unigrams
            .filter { $0.key.count > normalized.count && $0.key.hasPrefix(normalized) && $0.value >= 3 }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit)
            .map(\.key)
    }

    public func usageCount(for word: String) -> Int {
        Self.normalized(word).flatMap { storage.unigrams[$0] } ?? 0
    }

    // MARK: - Persistence

    public func persist() {
        guard unsavedChanges > 0, let defaults else { return }
        if let data = try? JSONEncoder().encode(storage) {
            defaults.set(data, forKey: Self.storageKey)
            unsavedChanges = 0
        }
    }

    // MARK: - Internals

    private func enforceLimits() {
        if storage.unigrams.count > Self.maximumUnigrams {
            // Halve counts so stale vocabulary decays, then drop the zeros.
            storage.unigrams = storage.unigrams
                .mapValues { $0 / 2 }
                .filter { $0.value > 0 }
        }
        if storage.bigrams.count > Self.maximumBigramContexts {
            storage.bigrams = Dictionary(
                storage.bigrams
                    .sorted { lhs, rhs in
                        lhs.value.values.reduce(0, +) > rhs.value.values.reduce(0, +)
                    }
                    .prefix(Self.maximumBigramContexts / 2)
                    .map { ($0.key, $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        for (context, continuations) in storage.bigrams
        where continuations.count > Self.maximumContinuationsPerContext {
            storage.bigrams[context] = Dictionary(
                continuations
                    .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
                    .prefix(Self.maximumContinuationsPerContext)
                    .map { ($0.key, $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    private static func normalized(_ word: String) -> String? {
        let trimmed = word.lowercased()
        guard !trimmed.isEmpty,
              trimmed.count <= maximumWordLength,
              trimmed.contains(where: \.isLetter),
              trimmed.allSatisfy({ $0.isLetter || $0 == "'" }) else {
            return nil
        }
        return trimmed
    }
}
