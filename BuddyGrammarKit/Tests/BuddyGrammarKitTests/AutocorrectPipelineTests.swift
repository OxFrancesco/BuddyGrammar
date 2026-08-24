import XCTest
@testable import BuddyGrammarKit

/// End-to-end autocorrect quality through the same seam the keyboard's word
/// boundary uses: platform spell-check candidates merged with lexicon-backed
/// fuzzy corrections, re-weighted by the preceding word.
final class AutocorrectPipelineTests: XCTestCase {
    private func makeIntelligence() -> TextIntelligence {
        TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(defaults: nil),
            lexicon: .shared
        )
    }

    private func correction(
        _ intelligence: TextIntelligence,
        for context: String,
        guesses: [String],
        flagged: Bool = false,
        language: String = "en-US"
    ) -> TextSuggestion? {
        intelligence.suggestions(
            for: context,
            spellingCandidates: guesses,
            isPlatformWordFlagged: flagged,
            languageCode: language,
            limit: 3
        ).first { $0.kind == .correction }
    }

    func testFrequencyRankingPicksTheCommonWordAmongPlatformGuesses() throws {
        let intelligence = makeIntelligence()
        // Apple returns unranked guesses; "teh" should resolve to "the"
        // because our frequency priors outrank rarer near-misses.
        let result = try XCTUnwrap(
            correction(intelligence, for: "teh", guesses: ["ten", "tech", "the"])
        )
        XCTAssertEqual(result.text, "the")
    }

    func testLexiconProposesWhatPlatformGuessesMissed() throws {
        let intelligence = makeIntelligence()
        let result = try XCTUnwrap(
            correction(intelligence, for: "recieve", guesses: ["receive", "relieve"])
        )
        XCTAssertEqual(result.text.lowercased(), "receive")
    }

    func testLexiconChannelEngagesWhenCheckerFlagsButHasNoGuesses() throws {
        let intelligence = makeIntelligence()
        // The checker flags the word but returns nothing usable; the bundled
        // lexicon supplies the fix.
        let result = try XCTUnwrap(
            correction(
                intelligence,
                for: "recieve",
                guesses: [],
                flagged: true
            )
        )
        XCTAssertEqual(result.text.lowercased(), "receive")
    }

    func testPrecedingWordBreaksDistanceTiesTowardContext() throws {
        let intelligence = makeIntelligence()
        // Both "quite" and "quiet" sit one transposition from "qiuet"-style
        // typos; the personal model learned which continuation follows "very".
        intelligence.observeCommittedText(
            "very quiet",
            precededBy: nil,
            languageCode: "en-US"
        )
        intelligence.observeCommittedText(
            "very quiet",
            precededBy: nil,
            languageCode: "en-US"
        )

        let result = try XCTUnwrap(
            correction(
                intelligence,
                for: "very quet",
                guesses: ["quit", "quiet", "quest"]
            )
        )
        XCTAssertEqual(result.text.lowercased(), "quiet")
    }

    func testItalianAccentRestorationFlowsThroughThePipeline() throws {
        let intelligence = makeIntelligence()
        // Checker flags "perche" without producing the accented form; the
        // lexicon channel restores it because both share QWERTY geometry.
        let result = try XCTUnwrap(
            correction(
                intelligence,
                for: "e perche",
                guesses: [],
                flagged: true,
                language: "it-IT"
            )
        )
        XCTAssertEqual(result.text, "perché")
    }

    func testCorrectionPathStaysUnderAKeystrokeBudgetInRelease() {
        // Whole suggestion refresh (fuzzy scan + ranking) per simulated
        // pause; runs only as a wall-clock smoke check in any configuration.
        let intelligence = makeIntelligence()
        _ = intelligence.suggestions(
            for: "teh",
            spellingCandidates: ["ten", "the"],
            languageCode: "en-US",
            limit: 3
        )
        measure {
            for context in ["teh", "I recieve", "she said teh", "dont stop"] {
                _ = intelligence.suggestions(
                    for: context,
                    spellingCandidates: ["guess"],
                    languageCode: "en-US",
                    limit: 3
                )
            }
        }
    }
}
