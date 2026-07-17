import Foundation

/// Learns the user's own unigram, bigram, and trigram frequencies from what
/// they type so predictions and completions adapt to their vocabulary.
///
/// Counts are stored in the provided `UserDefaults` (the keyboard extension's
/// own container, so nothing leaves the device) and capped with periodic
/// halving so old habits decay instead of dominating forever.
public final class PersonalLanguageModel {
    private struct Storage: Codable {
        var unigrams: [String: Int] = [:]
        var bigrams: [String: [String: Int]] = [:]
        var trigrams: [String: [String: Int]] = [:]
        var lastDecayAt: Date? = nil

        private enum CodingKeys: String, CodingKey {
            case unigrams
            case bigrams
            case trigrams
            case lastDecayAt
        }

        init() {}

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            unigrams = try container.decodeIfPresent(
                [String: Int].self,
                forKey: .unigrams
            ) ?? [:]
            bigrams = try container.decodeIfPresent(
                [String: [String: Int]].self,
                forKey: .bigrams
            ) ?? [:]
            trigrams = try container.decodeIfPresent(
                [String: [String: Int]].self,
                forKey: .trigrams
            ) ?? [:]
            lastDecayAt = try container.decodeIfPresent(Date.self, forKey: .lastDecayAt)
        }
    }

    private static let storageKey = "personalLanguageModel.v1"
    private static let maximumUnigrams = 3_000
    private static let maximumBigramContexts = 1_500
    private static let maximumTrigramContexts = 1_500
    private static let maximumContinuationsPerContext = 6
    private static let saveInterval = 20
    private static let maximumWordLength = 24
    private static let namespaceSeparator = "\u{1E}"
    private static let decayInterval: TimeInterval = 30 * 24 * 60 * 60

    private var storage: Storage
    private let defaults: UserDefaults?
    private let now: () -> Date
    private var unsavedChanges = 0

    public init(
        defaults: UserDefaults? = .standard,
        now: @escaping () -> Date = { .now }
    ) {
        self.defaults = defaults
        self.now = now
        if let data = defaults?.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Storage.self, from: data) {
            storage = decoded
        } else {
            storage = Storage()
        }
        if storage.lastDecayAt == nil {
            storage.lastDecayAt = now()
        }
    }

    // MARK: - Learning

    public func learn(
        previousWord: String?,
        word: String,
        languageCode: String? = nil
    ) {
        learn(
            previousWords: previousWord.map { [$0] } ?? [],
            word: word,
            languageCode: languageCode
        )
    }

    public func learn(
        previousWords: [String],
        word: String,
        languageCode: String? = nil
    ) {
        applyTimeDecayIfNeeded()
        guard let word = Self.normalized(word) else { return }
        let context = previousWords.compactMap(Self.normalized).suffix(2)
        let namespace = Self.namespacePrefix(for: languageCode)
        storage.unigrams[namespace + word, default: 0] += 1
        if let previous = context.last {
            storage.bigrams[namespace + previous, default: [:]][word, default: 0] += 1
        }
        if context.count == 2 {
            let key = namespace + Self.trigramKey(Array(context))
            storage.trigrams[key, default: [:]][word, default: 0] += 1
        }
        enforceLimits()
        unsavedChanges += 1
        if unsavedChanges >= Self.saveInterval {
            persist()
        }
    }

    /// Removes one observation when the user explicitly reverts, deletes, or
    /// replaces a learned word. Negative feedback is never inferred from the
    /// model's own output; callers must provide a confirmed outcome.
    public func reject(
        previousWord: String?,
        word: String,
        languageCode: String? = nil
    ) {
        reject(
            previousWords: previousWord.map { [$0] } ?? [],
            word: word,
            languageCode: languageCode
        )
    }

    public func reject(
        previousWords: [String],
        word: String,
        languageCode: String? = nil
    ) {
        applyTimeDecayIfNeeded()
        guard let word = Self.normalized(word) else { return }
        let context = previousWords.compactMap(Self.normalized).suffix(2)
        let namespace = Self.namespacePrefix(for: languageCode)
        var changed = Self.decrement(word: namespace + word, in: &storage.unigrams)

        if let previous = context.last {
            let key = namespace + previous
            changed = Self.decrement(
                word: word,
                in: &storage.bigrams[key, default: [:]]
            ) || changed
            if storage.bigrams[key]?.isEmpty == true {
                storage.bigrams.removeValue(forKey: key)
            }
        }
        if context.count == 2 {
            let key = namespace + Self.trigramKey(Array(context))
            changed = Self.decrement(
                word: word,
                in: &storage.trigrams[key, default: [:]]
            ) || changed
            if storage.trigrams[key]?.isEmpty == true {
                storage.trigrams.removeValue(forKey: key)
            }
        }

        if changed {
            unsavedChanges += 1
        }
    }

    /// Learns every word in committed text, preserving up to two words of
    /// surrounding context while never linking predictions across sentences.
    public func learn(
        text: String,
        precededBy precedingContext: String? = nil,
        languageCode: String? = nil
    ) {
        var previousWords = TextWordTokenizer.trailingSentenceWords(
            in: precedingContext ?? ""
        )
        for (index, sentence) in TextWordTokenizer.sentenceSegments(in: text).enumerated() {
            if index > 0 {
                previousWords.removeAll(keepingCapacity: true)
            }
            for word in sentence {
                learn(
                    previousWords: previousWords,
                    word: word,
                    languageCode: languageCode
                )
                previousWords.append(word)
                previousWords = Array(previousWords.suffix(2))
            }
        }
    }

    // MARK: - Predictions

    /// Next words the user has typed after `previousWord`, most frequent first.
    public func predictions(
        after previousWord: String?,
        languageCode: String? = nil,
        limit: Int
    ) -> [String] {
        predictions(
            after: previousWord.map { [$0] } ?? [],
            languageCode: languageCode,
            limit: limit
        )
    }

    /// Next words for the most specific available context. Two-word context
    /// is considered first and then blended with the one-word fallback.
    public func predictions(
        after previousWords: [String],
        languageCode: String? = nil,
        limit: Int
    ) -> [String] {
        applyTimeDecayIfNeeded()
        guard limit > 0 else { return [] }
        let context = previousWords.compactMap(Self.normalized).suffix(2)
        let namespace = Self.namespacePrefix(for: languageCode)
        var results: [String] = []

        func append(_ continuations: [String: Int]?) {
            guard let continuations else { return }
            for candidate in Self.ranked(continuations)
            where !results.contains(candidate) {
                results.append(candidate)
                if results.count == limit { return }
            }
        }

        if context.count == 2 {
            append(storage.trigrams[namespace + Self.trigramKey(Array(context))])
        }
        if results.count < limit, let previous = context.last {
            append(storage.bigrams[namespace + previous])
        }
        return Array(results.prefix(limit))
    }

    /// The user's own words starting with `prefix`, most used first.
    public func completions(
        forPrefix prefix: String,
        languageCode: String? = nil,
        limit: Int
    ) -> [String] {
        applyTimeDecayIfNeeded()
        guard limit > 0, let normalized = Self.normalized(prefix) else { return [] }
        let namespace = Self.namespacePrefix(for: languageCode)
        let scopedPrefix = namespace + normalized
        return storage.unigrams
            .filter {
                $0.key.hasPrefix(scopedPrefix)
                    && $0.key.count > namespace.count + normalized.count
                    && $0.value >= 3
            }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit)
            .map { String($0.key.dropFirst(namespace.count)) }
    }

    public func usageCount(
        for word: String,
        languageCode: String? = nil
    ) -> Int {
        applyTimeDecayIfNeeded()
        guard let word = Self.normalized(word) else { return 0 }
        return storage.unigrams[Self.namespacePrefix(for: languageCode) + word] ?? 0
    }

    // MARK: - Persistence

    public func persist() {
        guard unsavedChanges > 0, let defaults else { return }
        if let data = try? JSONEncoder().encode(storage) {
            defaults.set(data, forKey: Self.storageKey)
            unsavedChanges = 0
        }
    }

    /// Removes both the live aggregate and its durable on-device snapshot.
    public func reset() {
        storage = Storage()
        storage.lastDecayAt = now()
        unsavedChanges = 0
        defaults?.removeObject(forKey: Self.storageKey)
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
        if storage.trigrams.count > Self.maximumTrigramContexts {
            storage.trigrams = Dictionary(
                storage.trigrams
                    .sorted { lhs, rhs in
                        lhs.value.values.reduce(0, +) > rhs.value.values.reduce(0, +)
                    }
                    .prefix(Self.maximumTrigramContexts / 2)
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
        for (context, continuations) in storage.trigrams
        where continuations.count > Self.maximumContinuationsPerContext {
            storage.trigrams[context] = Dictionary(
                continuations
                    .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
                    .prefix(Self.maximumContinuationsPerContext)
                    .map { ($0.key, $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    private func applyTimeDecayIfNeeded() {
        let referenceDate = now()
        guard let lastDecayAt = storage.lastDecayAt else {
            storage.lastDecayAt = referenceDate
            return
        }
        let elapsed = referenceDate.timeIntervalSince(lastDecayAt)
        guard elapsed >= Self.decayInterval else { return }

        let intervals = min(12, Int(elapsed / Self.decayInterval))
        for _ in 0..<intervals {
            storage.unigrams = storage.unigrams
                .mapValues { $0 / 2 }
                .filter { $0.value > 0 }
            storage.bigrams = Self.halved(storage.bigrams)
            storage.trigrams = Self.halved(storage.trigrams)
        }
        storage.lastDecayAt = referenceDate
        unsavedChanges += 1
    }

    private static func halved(
        _ contexts: [String: [String: Int]]
    ) -> [String: [String: Int]] {
        contexts.reduce(into: [:]) { result, entry in
            let values = entry.value
                .mapValues { $0 / 2 }
                .filter { $0.value > 0 }
            if !values.isEmpty {
                result[entry.key] = values
            }
        }
    }

    private static func decrement(
        word: String,
        in counts: inout [String: Int]
    ) -> Bool {
        guard let count = counts[word], count > 0 else { return false }
        if count == 1 {
            counts.removeValue(forKey: word)
        } else {
            counts[word] = count - 1
        }
        return true
    }

    private static func ranked(_ continuations: [String: Int]) -> [String] {
        continuations
            .filter { $0.value >= 2 }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map(\.key)
    }

    private static func trigramKey(_ words: [String]) -> String {
        words.joined(separator: "\u{1F}")
    }

    /// English and unknown callers retain the original flat keys. Other
    /// primary languages use a prefix that normalized words can never contain,
    /// so older data remains readable without cross-language fallback.
    private static func namespacePrefix(for languageCode: String?) -> String {
        let primaryLanguage = LanguageSupport.primaryCode(for: languageCode)
        guard primaryLanguage != LanguageSupport.defaultPrimaryCode else {
            return ""
        }
        return namespaceSeparator + primaryLanguage + namespaceSeparator
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
