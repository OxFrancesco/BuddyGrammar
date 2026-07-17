import BuddyGrammarKit
import XCTest

final class PersonalLanguageModelTests: XCTestCase {

    private func makeModel() -> PersonalLanguageModel {
        PersonalLanguageModel(defaults: nil)
    }

    func testPredictsRepeatedContinuationsMostFrequentFirst() {
        let model = makeModel()
        for _ in 0..<3 {
            model.learn(previousWord: "see", word: "tomorrow")
        }
        for _ in 0..<2 {
            model.learn(previousWord: "see", word: "you")
        }
        XCTAssertEqual(model.predictions(after: "see", limit: 2), ["tomorrow", "you"])
    }

    func testIgnoresSingleOccurrenceContinuations() {
        let model = makeModel()
        model.learn(previousWord: "see", word: "tomorrow")
        XCTAssertEqual(model.predictions(after: "see", limit: 2), [])
    }

    func testCompletionsRequireRepeatedUse() {
        let model = makeModel()
        for _ in 0..<3 {
            model.learn(previousWord: nil, word: "francesco")
        }
        model.learn(previousWord: nil, word: "fabulous")
        XCTAssertEqual(model.completions(forPrefix: "f", limit: 2), ["francesco"])
        XCTAssertEqual(model.completions(forPrefix: "fra", limit: 2), ["francesco"])
    }

    func testExplicitRejectionRemovesMistakenVocabularyEvidence() {
        let model = makeModel()
        for _ in 0..<3 {
            model.learn(previousWord: "type", word: "teh")
        }

        XCTAssertEqual(model.usageCount(for: "teh"), 3)

        model.reject(previousWord: "type", word: "teh")

        XCTAssertEqual(model.usageCount(for: "teh"), 2)
        XCTAssertEqual(model.completions(forPrefix: "t", limit: 3), [])
    }

    func testOldCountsDecayWithElapsedTime() {
        var now = Date(timeIntervalSince1970: 1_000)
        let model = PersonalLanguageModel(defaults: nil, now: { now })
        for _ in 0..<8 {
            model.learn(previousWord: nil, word: "temporary")
        }
        XCTAssertEqual(model.usageCount(for: "temporary"), 8)

        now = now.addingTimeInterval(61 * 24 * 60 * 60)

        XCTAssertLessThanOrEqual(model.usageCount(for: "temporary"), 2)
    }

    func testRejectsNonWords() {
        let model = makeModel()
        for _ in 0..<3 {
            model.learn(previousWord: nil, word: "12345")
            model.learn(previousWord: nil, word: "http://x.co")
        }
        XCTAssertEqual(model.completions(forPrefix: "1", limit: 2), [])
        XCTAssertEqual(model.completions(forPrefix: "h", limit: 2), [])
    }

    func testPersistsAndReloadsCounts() throws {
        let suiteName = "PersonalLanguageModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = PersonalLanguageModel(defaults: defaults)
        for _ in 0..<3 {
            model.learn(previousWord: "ciao", word: "bella")
        }
        model.persist()

        let reloaded = PersonalLanguageModel(defaults: defaults)
        XCTAssertEqual(reloaded.predictions(after: "ciao", limit: 1), ["bella"])
    }

    func testResetDeletesInMemoryAndPersistedVocabulary() throws {
        let suiteName = "PersonalLanguageModelResetTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = PersonalLanguageModel(defaults: defaults)
        for _ in 0..<3 {
            model.learn(previousWord: nil, word: "privateword")
        }
        model.persist()

        model.reset()

        XCTAssertEqual(model.usageCount(for: "privateword"), 0)
        XCTAssertEqual(
            PersonalLanguageModel(defaults: defaults).usageCount(for: "privateword"),
            0
        )
    }

    func testPersonalPredictionsOutrankStaticBigrams() {
        let model = makeModel()
        for _ in 0..<2 {
            model.learn(previousWord: "good", word: "vibes")
        }
        XCTAssertEqual(
            NextWordPredictor.predictions(after: "good", personal: model, limit: 2),
            ["vibes", "morning"]
        )
    }

    func testLearnsAndPersistsTwoWordContexts() throws {
        let suiteName = "PersonalLanguageModelTrigramTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = PersonalLanguageModel(defaults: defaults)
        for _ in 0..<2 {
            model.learn(previousWords: ["good", "morning"], word: "team")
            model.learn(previousWords: ["tomorrow", "morning"], word: "flight")
        }
        model.persist()

        let reloaded = PersonalLanguageModel(defaults: defaults)
        XCTAssertEqual(
            reloaded.predictions(after: ["good", "morning"], limit: 1),
            ["team"]
        )
        XCTAssertEqual(
            reloaded.predictions(after: ["tomorrow", "morning"], limit: 1),
            ["flight"]
        )
    }

    func testLoadsLegacyStorageWithoutTrigramData() throws {
        let suiteName = "PersonalLanguageModelLegacyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            Data(#"{"unigrams":{"legacy":3},"bigrams":{"see":{"you":2}}}"#.utf8),
            forKey: "personalLanguageModel.v1"
        )

        let reloaded = PersonalLanguageModel(defaults: defaults)

        XCTAssertEqual(reloaded.completions(forPrefix: "leg", limit: 1), ["legacy"])
        XCTAssertEqual(reloaded.predictions(after: "see", limit: 1), ["you"])
        XCTAssertEqual(
            reloaded.predictions(after: "see", languageCode: "en-GB", limit: 1),
            ["you"]
        )
        XCTAssertEqual(
            reloaded.predictions(after: "see", languageCode: "it-IT", limit: 1),
            []
        )
    }

    func testEnglishLanguageCodesShareTheLegacyUnscopedCorpus() {
        let model = makeModel()
        for _ in 0..<2 {
            model.learn(previousWord: "see", word: "tomorrow", languageCode: "en-US")
        }

        XCTAssertEqual(model.predictions(after: "see", limit: 1), ["tomorrow"])
        XCTAssertEqual(
            model.predictions(after: "see", languageCode: "en-GB", limit: 1),
            ["tomorrow"]
        )
    }

    func testISO639ThreeLetterCodesShareCanonicalLanguageScopes() {
        XCTAssertEqual(LanguageSupport.primaryCode(for: "eng"), "en")
        XCTAssertEqual(LanguageSupport.primaryCode(for: "ita"), "it")

        let model = makeModel()
        for _ in 0..<2 {
            model.learn(previousWord: "see", word: "tomorrow", languageCode: "eng")
            model.learn(previousWord: "ciao", word: "bella", languageCode: "it-IT")
        }

        XCTAssertEqual(
            model.predictions(after: "see", languageCode: "en-US", limit: 1),
            ["tomorrow"]
        )
        XCTAssertEqual(
            model.predictions(after: "ciao", languageCode: "ita", limit: 1),
            ["bella"]
        )
    }

    func testLanguageNamespacesIsolatePredictionsAndUsage() {
        let model = makeModel()
        for _ in 0..<2 {
            model.learn(previousWord: "ciao", word: "hello", languageCode: "en-US")
            model.learn(previousWord: "ciao", word: "bella", languageCode: "it-IT")
        }

        XCTAssertEqual(
            model.predictions(after: "ciao", languageCode: "en-US", limit: 2),
            ["hello"]
        )
        XCTAssertEqual(
            model.predictions(after: "ciao", languageCode: "it-CH", limit: 2),
            ["bella"]
        )
        XCTAssertEqual(model.usageCount(for: "bella", languageCode: "en-US"), 0)
        XCTAssertEqual(model.usageCount(for: "bella", languageCode: "it-IT"), 2)
    }

    func testItalianNamespacePersistsAndDoesNotLeakIntoEnglishCompletions() throws {
        let suiteName = "PersonalLanguageModelLanguageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = PersonalLanguageModel(defaults: defaults)
        for _ in 0..<3 {
            model.learn(previousWord: "ciao", word: "italiano", languageCode: "it_IT")
        }
        model.persist()

        let reloaded = PersonalLanguageModel(defaults: defaults)
        XCTAssertEqual(
            reloaded.predictions(after: "ciao", languageCode: "it-CH", limit: 1),
            ["italiano"]
        )
        XCTAssertEqual(
            reloaded.completions(forPrefix: "it", languageCode: "it-IT", limit: 1),
            ["italiano"]
        )
        XCTAssertEqual(reloaded.predictions(after: "ciao", limit: 1), [])
        XCTAssertEqual(reloaded.completions(forPrefix: "it", limit: 1), [])
    }
}

final class WordFrequencyLexiconTests: XCTestCase {

    func testCompletionsAreFrequencyRankedNotAlphabetical() {
        let completions = WordFrequencyLexicon.shared.completions(forPrefix: "th", limit: 3)
        XCTAssertEqual(completions.first, "the")
        XCTAssertEqual(completions.count, 3)
    }

    func testCompletionsIgnoreCaseOfPrefix() {
        XCTAssertEqual(
            WordFrequencyLexicon.shared.completions(forPrefix: "Th", limit: 1),
            ["the"]
        )
    }

    func testRankOfCommonWordIsLow() throws {
        let rank = try XCTUnwrap(WordFrequencyLexicon.shared.rank(of: "the"))
        XCTAssertLessThan(rank, 10)
    }
}
