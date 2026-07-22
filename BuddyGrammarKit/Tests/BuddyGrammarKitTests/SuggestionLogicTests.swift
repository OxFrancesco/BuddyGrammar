import XCTest
@testable import BuddyGrammarKit

final class SuggestionLogicTests: XCTestCase {
    func testEmojiMapMatchesCaseInsensitively() {
        XCTAssertEqual(SuggestionEmojiMap.emoji(for: "fire"), "🔥")
        XCTAssertEqual(SuggestionEmojiMap.emoji(for: "FIRE"), "🔥")
        XCTAssertEqual(SuggestionEmojiMap.emoji(for: "100"), "💯")
        XCTAssertEqual(SuggestionEmojiMap.emoji(for: "Thanks"), "🙏")
        XCTAssertNil(SuggestionEmojiMap.emoji(for: "grammar"))
    }

    func testNextWordPredictorUsesBigramsThenFallback() {
        XCTAssertEqual(NextWordPredictor.predictions(after: "thank"), ["you", "the"])
        XCTAssertEqual(NextWordPredictor.predictions(after: "good"), ["morning", "luck"])
        XCTAssertEqual(NextWordPredictor.predictions(after: "How"), ["are", "much"])
        XCTAssertEqual(NextWordPredictor.predictions(after: nil), ["the", "I"])
        XCTAssertEqual(NextWordPredictor.predictions(after: "zzzunknown"), ["the", "I"])
        XCTAssertEqual(NextWordPredictor.predictions(after: "thank", limit: 3), ["you", "the", "I"])
    }

    func testAnalyzerDetectsPartialWord() {
        let analysis = TypingContextAnalyzer.analyze("Hello ther")
        XCTAssertEqual(analysis.mode, .typingWord("ther"))
        XCTAssertFalse(analysis.isAtSentenceStart)
    }

    func testAnalyzerDetectsSentenceStartForPartialWord() {
        let analysis = TypingContextAnalyzer.analyze("Done. Ne")
        XCTAssertEqual(analysis.mode, .typingWord("Ne"))
        XCTAssertTrue(analysis.isAtSentenceStart)
    }

    func testAnalyzerDetectsWordBoundary() {
        let analysis = TypingContextAnalyzer.analyze("thank ")
        XCTAssertEqual(analysis.mode, .betweenWords(lastWord: "thank"))
        XCTAssertFalse(analysis.isAtSentenceStart)
    }

    func testEmojiReplacementTargetIncludesAllTrailingSpacesAndTabs() {
        let cases = [
            (context: "Before thanks   ", target: "thanks   "),
            (context: "Before thanks \t\t", target: "thanks \t\t"),
        ]

        for item in cases {
            let analysis = TypingContextAnalyzer.analyze(item.context)
            XCTAssertEqual(analysis.mode, .betweenWords(lastWord: "thanks"))
            XCTAssertEqual(SuggestionEmojiMap.emoji(for: "thanks"), "🙏")
            XCTAssertEqual(
                TypingContextAnalyzer.rawTrailingWordAndHorizontalWhitespace(
                    in: item.context
                ),
                item.target
            )
        }
    }

    func testAnalyzerDetectsSentenceEnd() {
        let analysis = TypingContextAnalyzer.analyze("All done. ")
        XCTAssertEqual(analysis.mode, .betweenWords(lastWord: nil))
        XCTAssertTrue(analysis.isAtSentenceStart)
    }

    func testAnalyzerHandlesEmptyContext() {
        XCTAssertEqual(TypingContextAnalyzer.analyze(nil).mode, .empty)
        XCTAssertEqual(TypingContextAnalyzer.analyze("   ").mode, .empty)
        XCTAssertTrue(TypingContextAnalyzer.analyze("").isAtSentenceStart)
    }

    func testLocalWordCorrectorPrefersNearbyKeyboardTypos() {
        XCTAssertEqual(
            LocalWordCorrector.bestCorrection(
                for: "fhag",
                candidates: ["flag", "that"]
            ),
            "that"
        )
        XCTAssertEqual(
            LocalWordCorrector.bestCorrection(
                for: "Fhag",
                candidates: ["flag", "that"]
            ),
            "That"
        )
    }

    func testLocalWordCorrectorRejectsUnrelatedGuess() {
        XCTAssertNil(
            LocalWordCorrector.bestCorrection(
                for: "cat",
                candidates: ["xylophone"]
            )
        )
    }

    func testHandwritingAllCapsIsLowercasedInsideASentence() {
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion(
                "HELLO WORLD",
                contextBeforeInput: "I wrote "
            ),
            "hello world"
        )
    }

    func testHandwritingAllCapsUsesSentenceCaseAtSentenceStart() {
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion(
                "HELLO WORLD",
                contextBeforeInput: "Previous sentence. "
            ),
            "Hello world"
        )
    }

    func testHandwritingLowercasesTitleCaseWordInsideASentence() {
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion(
                "Hello world",
                contextBeforeInput: "I wrote "
            ),
            "hello world"
        )
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion(
                "The",
                contextBeforeInput: "jumped over "
            ),
            "the"
        )
    }

    func testHandwritingCapitalizesLowercaseTextAtSentenceStart() {
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion(
                "hello world",
                contextBeforeInput: "Previous sentence. "
            ),
            "Hello world"
        )
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion(
                "hello",
                contextBeforeInput: nil
            ),
            "Hello"
        )
    }

    func testHandwritingKeepsAcronymsAndContractionsOfIInsideASentence() {
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion(
                "NASA launch",
                contextBeforeInput: "about the "
            ),
            "NASA launch"
        )
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion(
                "I'm here",
                contextBeforeInput: "then "
            ),
            "I'm here"
        )
    }

    func testHandwritingPreservesMixedCaseAndSingleLetterI() {
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion(
                "BuddyGrammar iOS",
                contextBeforeInput: "Using "
            ),
            "BuddyGrammar iOS"
        )
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion("I", contextBeforeInput: "and "),
            "I"
        )
    }

    func testHandwritingPreservesNonEnglishRecognizerCasingAndText() {
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion(
                "i bambini",
                contextBeforeInput: "vedo ",
                languageCode: "ita"
            ),
            "i bambini"
        )
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion(
                "Haus",
                contextBeforeInput: "das ",
                languageCode: "de-DE"
            ),
            "Haus"
        )
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion(
                "HAUS",
                contextBeforeInput: "das ",
                languageCode: "deu"
            ),
            "HAUS"
        )
    }

    func testHandwritingStillAppliesEnglishPronounRule() {
        XCTAssertEqual(
            HandwritingTextFormatter.textForInsertion(
                "i agree",
                contextBeforeInput: "and ",
                languageCode: "eng"
            ),
            "I agree"
        )
    }
}
