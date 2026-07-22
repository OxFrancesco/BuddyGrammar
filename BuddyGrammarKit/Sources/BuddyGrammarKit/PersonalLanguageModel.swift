import Foundation

/// Learns the user's own unigram, bigram, and trigram frequencies from what
/// they type so predictions and completions adapt to their vocabulary.
///
/// Counts are stored in the provided `UserDefaults` (the keyboard extension's
/// own container, so nothing leaves the device) and capped with periodic
/// halving so old habits decay instead of dominating forever.
public final class PersonalLanguageModel {
    private struct Storage: Codable {
        var resetGeneration: UInt64 = 0
        var unigrams: [String: Int] = [:]
        var bigrams: [String: [String: Int]] = [:]
        var trigrams: [String: [String: Int]] = [:]
        var explicitWords: Set<String> = []
        var suppressedCorrections: Set<String> = []
        var lastDecayAt: Date? = nil

        private enum CodingKeys: String, CodingKey {
            case resetGeneration
            case unigrams
            case bigrams
            case trigrams
            case explicitWords
            case suppressedCorrections
            case lastDecayAt
        }

        init(resetGeneration: UInt64 = 0) {
            self.resetGeneration = resetGeneration
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            resetGeneration = try container.decodeIfPresent(
                UInt64.self,
                forKey: .resetGeneration
            ) ?? 0
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
            explicitWords = try container.decodeIfPresent(
                Set<String>.self,
                forKey: .explicitWords
            ) ?? []
            suppressedCorrections = try container.decodeIfPresent(
                Set<String>.self,
                forKey: .suppressedCorrections
            ) ?? []
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
    private static let maximumCorrectionTextLength = 128
    private static let maximumExplicitWords = 1_000
    private static let maximumSuppressedCorrections = 1_000
    private static let namespaceSeparator = "\u{1E}"
    private static let correctionSeparator = "\u{1D}"
    private static let decayInterval: TimeInterval = 30 * 24 * 60 * 60

    private var storage: Storage
    private let defaults: UserDefaults?
    private let now: () -> Date
    private let resetGeneration: () -> UInt64
    private var unsavedChanges = 0

    public init(
        defaults: UserDefaults? = .standard,
        now: @escaping () -> Date = { .now },
        resetGeneration: @escaping () -> UInt64 = { 0 }
    ) {
        self.defaults = defaults
        self.now = now
        self.resetGeneration = resetGeneration
        let currentResetGeneration = resetGeneration()
        if let data = defaults?.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Storage.self, from: data),
           decoded.resetGeneration == currentResetGeneration {
            storage = decoded
        } else {
            storage = Storage(resetGeneration: currentResetGeneration)
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

    /// Keeps an explicitly accepted word available without fabricating typing
    /// observations or linking it to sentence context.
    @discardableResult
    public func addToDictionary(
        _ word: String,
        languageCode: String? = nil
    ) -> Bool {
        applyTimeDecayIfNeeded()
        guard storage.explicitWords.count < Self.maximumExplicitWords,
              let normalized = Self.normalized(word) else { return false }
        let key = Self.namespacePrefix(for: languageCode) + normalized
        guard storage.explicitWords.insert(key).inserted else { return false }
        unsavedChanges += 1
        return true
    }

    /// Suppresses one exact automatic-correction pair. The replacement remains
    /// usable elsewhere; for example, rejecting `teh → the` never blacklists
    /// the word “the” globally.
    @discardableResult
    public func suppressCorrection(
        typed: String,
        suggestion: String,
        languageCode: String? = nil
    ) -> Bool {
        applyTimeDecayIfNeeded()
        guard storage.suppressedCorrections.count < Self.maximumSuppressedCorrections,
              let typed = Self.normalizedCorrectionText(typed),
              let suggestion = Self.normalizedCorrectionText(suggestion),
              typed != suggestion else { return false }
        let key = Self.correctionPreferenceKey(
            typed: typed,
            suggestion: suggestion,
            languageCode: languageCode
        )
        guard storage.suppressedCorrections.insert(key).inserted else { return false }
        unsavedChanges += 1
        return true
    }

    public func isCorrectionSuppressed(
        typed: String,
        suggestion: String,
        languageCode: String? = nil
    ) -> Bool {
        synchronizeResetGenerationIfNeeded()
        guard let typed = Self.normalizedCorrectionText(typed),
              let suggestion = Self.normalizedCorrectionText(suggestion) else { return false }
        return storage.suppressedCorrections.contains(
            Self.correctionPreferenceKey(
                typed: typed,
                suggestion: suggestion,
                languageCode: languageCode
            )
        )
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
        let learned = storage.unigrams
            .filter {
                $0.key.hasPrefix(scopedPrefix)
                    && $0.key.count > namespace.count + normalized.count
                    && $0.value >= 3
            }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit)
            .map { String($0.key.dropFirst(namespace.count)) }
        let explicit = storage.explicitWords
            .filter {
                $0.hasPrefix(scopedPrefix)
                    && $0.count > namespace.count + normalized.count
            }
            .sorted()
            .map { String($0.dropFirst(namespace.count)) }
        return Array((explicit + learned).uniqued().prefix(limit))
    }

    public func usageCount(
        for word: String,
        languageCode: String? = nil
    ) -> Int {
        applyTimeDecayIfNeeded()
        guard let word = Self.normalized(word) else { return 0 }
        let key = Self.namespacePrefix(for: languageCode) + word
        return max(
            storage.unigrams[key] ?? 0,
            storage.explicitWords.contains(key) ? 3 : 0
        )
    }

    // MARK: - Persistence

    public func persist() {
        synchronizeResetGenerationIfNeeded()
        guard unsavedChanges > 0, let defaults else { return }
        if let data = try? JSONEncoder().encode(storage) {
            defaults.set(data, forKey: Self.storageKey)
            unsavedChanges = 0
        }
    }

    /// Removes both the live aggregate and its durable on-device snapshot.
    public func reset() {
        storage = Storage(resetGeneration: resetGeneration())
        storage.lastDecayAt = now()
        unsavedChanges = 0
        defaults?.removeObject(forKey: Self.storageKey)
    }

    /// Drops live personalization without deleting a valid durable snapshot.
    /// This is used when the keyboard temporarily loses App Group access.
    public func discardInMemoryPersonalization() {
        storage = Storage(resetGeneration: resetGeneration())
        storage.lastDecayAt = now()
        unsavedChanges = 0
    }

    /// Reloads the durable snapshot after shared-container access returns.
    /// Epoch-mismatched snapshots are ignored so a stale writer cannot revive
    /// data from before the most recent reset.
    public func reloadPersonalization() {
        let currentResetGeneration = resetGeneration()
        if let data = defaults?.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Storage.self, from: data),
           decoded.resetGeneration == currentResetGeneration {
            storage = decoded
        } else {
            storage = Storage(resetGeneration: currentResetGeneration)
            storage.lastDecayAt = now()
        }
        unsavedChanges = 0
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
        synchronizeResetGenerationIfNeeded()
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

    private func synchronizeResetGenerationIfNeeded() {
        let currentResetGeneration = resetGeneration()
        guard storage.resetGeneration != currentResetGeneration else { return }
        storage = Storage(resetGeneration: currentResetGeneration)
        storage.lastDecayAt = now()
        unsavedChanges = 0
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

    private static func correctionPreferenceKey(
        typed: String,
        suggestion: String,
        languageCode: String?
    ) -> String {
        namespacePrefix(for: languageCode)
            + typed
            + correctionSeparator
            + suggestion
    }

    private static func normalized(_ word: String) -> String? {
        let trimmed = WordTokenNormalizer.canonicalized(word.lowercased())
        guard !trimmed.isEmpty,
              trimmed.count <= maximumWordLength,
              trimmed.contains(where: \.isLetter),
              trimmed.allSatisfy({
                  $0.isLetter || $0 == WordTokenNormalizer.canonicalApostrophe
              }) else {
            return nil
        }
        return trimmed
    }

    /// Correction replacements can be phrases (for example a text shortcut),
    /// so their persisted identity is deliberately broader than a dictionary
    /// word while still excluding the separators used by the storage key.
    private static func normalizedCorrectionText(_ text: String) -> String? {
        let trimmed = WordTokenNormalizer.canonicalized(
            text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        )
        guard !trimmed.isEmpty,
              trimmed.count <= maximumCorrectionTextLength,
              trimmed.contains(where: \.isLetter),
              !trimmed.contains(namespaceSeparator),
              !trimmed.contains(correctionSeparator) else {
            return nil
        }
        return trimmed
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
