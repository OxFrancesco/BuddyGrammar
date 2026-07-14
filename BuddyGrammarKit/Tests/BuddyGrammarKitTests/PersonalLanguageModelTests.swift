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
