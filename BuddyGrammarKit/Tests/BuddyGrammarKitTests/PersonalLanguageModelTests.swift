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

    func testExplicitDictionaryWordsAreImmediateAndLanguageScoped() {
        let model = makeModel()

        XCTAssertTrue(model.addToDictionary("Caffè", languageCode: "it-IT"))
        XCTAssertEqual(model.usageCount(for: "caffè", languageCode: "it-CH"), 3)
        XCTAssertEqual(
            model.completions(forPrefix: "caf", languageCode: "it-IT", limit: 1),
            ["caffè"]
        )
        XCTAssertEqual(model.completions(forPrefix: "caf", limit: 1), [])
        XCTAssertFalse(model.addToDictionary("Caffè", languageCode: "it-CH"))
    }

    func testSuppressedCorrectionIsExactAndLanguageScoped() {
        let model = makeModel()

        XCTAssertTrue(
            model.suppressCorrection(
                typed: "teh",
                suggestion: "the",
                languageCode: "en-US"
            )
        )
        XCTAssertTrue(
            model.isCorrectionSuppressed(
                typed: "TEH",
                suggestion: "The",
                languageCode: "en-GB"
            )
        )
        XCTAssertFalse(
            model.isCorrectionSuppressed(
                typed: "teh",
                suggestion: "ten",
                languageCode: "en-US"
            )
        )
        XCTAssertFalse(
            model.isCorrectionSuppressed(
                typed: "teh",
                suggestion: "the",
                languageCode: "it-IT"
            )
        )
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

    func testPersistsExplicitDictionaryAndCorrectionPreferences() throws {
        let suiteName = "PersonalLanguageModelPreferenceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = PersonalLanguageModel(defaults: defaults)
        model.addToDictionary("Buddyword", languageCode: "en-US")
        model.suppressCorrection(
            typed: "buddyword",
            suggestion: "buddy word",
            languageCode: "en-US"
        )
        // Exact replacement phrases are valid because text shortcuts can
        // expand one token into multiple words. Persist a single-word pair as
        // well so both preference shapes survive a reload.
        model.suppressCorrection(
            typed: "buddywrod",
            suggestion: "buddyword",
            languageCode: "en-US"
        )
        model.persist()

        let reloaded = PersonalLanguageModel(defaults: defaults)
        XCTAssertEqual(reloaded.usageCount(for: "buddyword"), 3)
        XCTAssertTrue(
            reloaded.isCorrectionSuppressed(
                typed: "buddywrod",
                suggestion: "buddyword",
                languageCode: "en-GB"
            )
        )
        XCTAssertTrue(
            reloaded.isCorrectionSuppressed(
                typed: "buddyword",
                suggestion: "buddy word",
                languageCode: "en-US"
            )
        )
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

    func testLiveModelCannotRetainOrResurrectWordsAfterResetGenerationAdvances() throws {
        let suiteName = "PersonalLanguageModelGenerationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = SharedPreferences(defaults: defaults)
        let liveModel = preferences.makePersonalLanguageModel()
        for _ in 0..<3 {
            liveModel.learn(previousWord: nil, word: "persistedsecret")
        }
        liveModel.persist()
        for _ in 0..<3 {
            liveModel.learn(previousWord: nil, word: "unsavedsecret")
        }

        preferences.resetPersonalLanguageLearning()

        XCTAssertEqual(liveModel.usageCount(for: "persistedsecret"), 0)
        XCTAssertEqual(liveModel.usageCount(for: "unsavedsecret"), 0)
        liveModel.persist()
        let reloaded = preferences.makePersonalLanguageModel()
        XCTAssertEqual(reloaded.usageCount(for: "persistedsecret"), 0)
        XCTAssertEqual(reloaded.usageCount(for: "unsavedsecret"), 0)

        for _ in 0..<3 {
            liveModel.learn(previousWord: nil, word: "postreset")
        }
        liveModel.persist()
        XCTAssertEqual(
            preferences.makePersonalLanguageModel().usageCount(for: "postreset"),
            3
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

    func testItalianApostropheVariantsShareCanonicalPersonalModelKeys() {
        let model = makeModel()
        for _ in 0..<3 {
            model.learn(previousWord: "io", word: "l'ho", languageCode: "it-IT")
            model.learn(previousWord: "qui", word: "c’è", languageCode: "it-IT")
            model.learn(previousWord: "aspetta", word: "po’", languageCode: "it-IT")
        }

        XCTAssertEqual(model.usageCount(for: "l’ho", languageCode: "it-CH"), 3)
        XCTAssertEqual(model.usageCount(for: "l'ho", languageCode: "it-IT"), 3)
        XCTAssertEqual(
            model.predictions(after: "io", languageCode: "it-IT", limit: 1),
            ["l’ho"]
        )
        XCTAssertEqual(
            model.completions(forPrefix: "c'", languageCode: "it-IT", limit: 1),
            ["c’è"]
        )
        XCTAssertEqual(model.usageCount(for: "po'", languageCode: "it-IT"), 3)
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

    func testBundledLanguagePacksExposeExpectedCountsWithoutCrossLanguageFallback() {
        XCTAssertEqual(WordFrequencyLexicon.shared.wordCount(languageCode: "en-US"), 8_000)
        XCTAssertEqual(WordFrequencyLexicon.shared.wordCount(languageCode: "it-IT"), 1_096)
        XCTAssertNotNil(WordFrequencyLexicon.shared.rank(of: "home", languageCode: "en"))
        XCTAssertNil(WordFrequencyLexicon.shared.rank(of: "home", languageCode: "it"))
        XCTAssertNotNil(WordFrequencyLexicon.shared.rank(of: "dare", languageCode: "it"))
        XCTAssertNil(WordFrequencyLexicon.shared.rank(of: "dare", languageCode: "en"))
    }

    func testItalianGeometryLookupPreservesCanonicalDisplay() {
        XCTAssertEqual(
            WordFrequencyLexicon.shared.match(for: "perche", languageCode: "it")?.display,
            "perché"
        )
        XCTAssertEqual(
            WordFrequencyLexicon.shared.match(for: "l'ho", languageCode: "it")?.display,
            "l’ho"
        )
        XCTAssertEqual(
            WordFrequencyLexicon.shared.completions(
                forPrefix: "c'",
                languageCode: "it-IT",
                limit: 1
            ),
            ["c’è"]
        )
    }
}
