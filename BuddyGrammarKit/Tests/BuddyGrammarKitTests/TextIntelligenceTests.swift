import XCTest
@testable import BuddyGrammarKit

final class TextIntelligenceTests: XCTestCase {
    func testBundledCompletionsAreRankedAndLanguageScoped() {
        let intelligence = TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(defaults: nil)
        )

        XCTAssertEqual(
            intelligence.suggestions(
                for: "I went hom",
                languageCode: "en-US",
                limit: 1
            ).first?.text,
            "home"
        )
        XCTAssertEqual(
            intelligence.suggestions(
                for: "voglio dar",
                languageCode: "it-IT",
                limit: 1
            ).first?.text,
            "dare"
        )
        XCTAssertTrue(
            intelligence.suggestions(
                for: "voglio hom",
                languageCode: "it-IT",
                limit: 3
            ).allSatisfy { $0.text.lowercased() != "home" }
        )
    }

    func testItalianCompletionsCanonicalizeAccentsAndApostrophes() {
        let intelligence = TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(defaults: nil)
        )

        XCTAssertEqual(
            intelligence.suggestions(
                for: "perc",
                languageCode: "it-IT",
                limit: 1
            ).first?.text,
            "perché"
        )
        XCTAssertEqual(
            intelligence.suggestions(
                for: "l'h",
                languageCode: "it-IT",
                limit: 1
            ).first?.text,
            "l’ho"
        )
        XCTAssertEqual(
            intelligence.suggestions(
                for: "c’",
                languageCode: "it-IT",
                limit: 1
            ).first?.text,
            "c’è"
        )
        XCTAssertEqual(
            TextWordTokenizer.words(in: "l’ho detto: c’è, però po’ dopo"),
            ["l’ho", "detto", "c’è", "però", "po’", "dopo"]
        )
    }
    func testTwoWordContextDisambiguatesPersonalPredictions() {
        let model = PersonalLanguageModel(defaults: nil)
        let intelligence = TextIntelligence(personalLanguageModel: model)

        for _ in 0..<2 {
            intelligence.observeCommittedText("good morning team", precededBy: nil)
            intelligence.observeCommittedText("tomorrow morning flight", precededBy: nil)
        }

        XCTAssertEqual(
            intelligence.suggestions(for: "good morning ", limit: 2).first,
            TextSuggestion(text: "team", kind: .prediction, replacementLength: 0)
        )
        XCTAssertEqual(
            intelligence.suggestions(for: "tomorrow morning ", limit: 2).first,
            TextSuggestion(text: "flight", kind: .prediction, replacementLength: 0)
        )
    }

    func testRecognizedPhraseLearnsItsSurroundingContext() {
        let model = PersonalLanguageModel(defaults: nil)
        let intelligence = TextIntelligence(personalLanguageModel: model)

        for _ in 0..<2 {
            intelligence.observeCommittedText("tomorrow morning", precededBy: "see you ")
        }

        XCTAssertEqual(
            intelligence.suggestions(for: "see you ", limit: 1).map(\.text),
            ["tomorrow"]
        )
        XCTAssertEqual(
            intelligence.suggestions(for: "you tomorrow ", limit: 1).map(\.text),
            ["morning"]
        )
    }

    func testClearCorrectionRanksAheadOfPrefixCompletions() {
        let intelligence = TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(defaults: nil)
        )

        let suggestions = intelligence.suggestions(
            for: "teh",
            spellingCandidates: ["the"],
            completionCandidates: ["tehran"],
            limit: 3
        )

        XCTAssertEqual(
            suggestions.first,
            TextSuggestion(
                text: "the",
                kind: .correction,
                replacementLength: 3,
                automaticCorrectionSource: .spelling
            )
        )
    }

    func testNeverSuggestSuppressesOnlyTheChosenCorrectionPair() {
        let intelligence = TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(defaults: nil)
        )
        XCTAssertTrue(
            intelligence.neverSuggestCorrection(
                typed: "teh",
                suggestion: "the",
                languageCode: "en-US"
            )
        )

        XCTAssertFalse(
            intelligence.suggestions(
                for: "teh",
                spellingCandidates: ["the"],
                languageCode: "en-GB",
                limit: 3
            ).contains(where: { $0.kind == .correction })
        )
        XCTAssertEqual(
            intelligence.suggestions(
                for: "teh",
                spellingCandidates: ["ten"],
                languageCode: "en-US",
                limit: 1
            ).first?.text,
            "ten"
        )
    }

    func testAddToDictionaryImmediatelyProtectsAcceptedSpelling() {
        let intelligence = TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(defaults: nil)
        )
        XCTAssertTrue(intelligence.addToDictionary("teh", languageCode: "en-US"))

        XCTAssertFalse(
            intelligence.suggestions(
                for: "teh",
                spellingCandidates: ["the"],
                languageCode: "en-US",
                limit: 3
            ).contains(where: { $0.kind == .correction })
        )
    }

    func testExactShortcutReplacementBypassesSpellingDistance() {
        let intelligence = TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(defaults: nil)
        )

        XCTAssertEqual(
            intelligence.suggestions(
                for: "omw",
                shortcutReplacement: "On my way!",
                spellingCandidates: ["own"],
                limit: 1
            ),
            [
                TextSuggestion(
                    text: "On my way!",
                    kind: .correction,
                    replacementLength: 3,
                    automaticCorrectionSource: .shortcut
                )
            ]
        )
    }

    func testNeverSuggestAlsoSuppressesTheExactShortcutPair() {
        let intelligence = TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(defaults: nil)
        )
        XCTAssertTrue(
            intelligence.neverSuggestCorrection(
                typed: "omw",
                suggestion: "On my way!",
                languageCode: "en-US"
            )
        )

        XCTAssertFalse(
            intelligence.suggestions(
                for: "omw",
                shortcutReplacement: "On my way!",
                languageCode: "en-US",
                limit: 3
            ).contains(where: { $0.kind == .correction })
        )
    }

    func testPersonalVocabularyRequiresRepeatedEvidenceBeforeSuppressingCorrection() {
        let intelligence = TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(defaults: nil)
        )
        intelligence.observeCommittedText(
            "teh",
            precededBy: nil,
            languageCode: "en-US"
        )

        XCTAssertEqual(
            intelligence.suggestions(
                for: "teh",
                spellingCandidates: ["the"],
                languageCode: "en-US",
                limit: 1
            ).first?.kind,
            .correction
        )

        for _ in 0..<2 {
            intelligence.observeCommittedText(
                "teh",
                precededBy: nil,
                languageCode: "en-US"
            )
        }

        XCTAssertFalse(
            intelligence.suggestions(
                for: "teh",
                spellingCandidates: ["the"],
                languageCode: "en-US",
                limit: 3
            ).contains(where: { $0.kind == .correction })
        )
        XCTAssertEqual(
            intelligence.suggestions(
                for: "teh",
                spellingCandidates: ["the"],
                languageCode: "it-IT",
                limit: 1
            ).first?.kind,
            .correction
        )
    }

    func testPrefixMatchRemainsACompletionInsteadOfACorrection() {
        let intelligence = TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(defaults: nil)
        )

        let suggestions = intelligence.suggestions(
            for: "hel",
            spellingCandidates: ["help"],
            completionCandidates: ["hel"],
            limit: 1
        )

        XCTAssertEqual(
            suggestions,
            [TextSuggestion(text: "help", kind: .completion, replacementLength: 3)]
        )
    }

    func testRecognizedTextInsertionUsesContextAwareSpacing() {
        XCTAssertEqual(
            RecognizedTextFormatter.textForInsertion("hello", contextBeforeInput: "Say"),
            " hello"
        )
        XCTAssertEqual(
            RecognizedTextFormatter.textForInsertion(", please", contextBeforeInput: "Hello"),
            ", please"
        )
        XCTAssertEqual(
            RecognizedTextFormatter.textForInsertion("hello", contextBeforeInput: "("),
            "hello"
        )
        XCTAssertEqual(
            RecognizedTextFormatter.textForInsertion("  hello  ", contextBeforeInput: nil),
            "hello"
        )

        let context = "Hello \t"
        let deleteCount = RecognizedTextFormatter.whitespaceToDeleteBefore(
            ", thanks",
            contextBeforeInput: context
        )
        let retainedContext = String(context.dropLast(deleteCount))
        let insertion = RecognizedTextFormatter.textForInsertion(
            ", thanks",
            contextBeforeInput: retainedContext
        )
        XCTAssertEqual(deleteCount, 2)
        XCTAssertEqual(retainedContext + insertion, "Hello, thanks")
    }

    func testObservedFinalWordIsConsumedExactlyOnceAtAnUnchangedBoundary() {
        var observed = ObservedTextSuffix(maximumCharacters: 8)
        observed.observe(
            committedText: "recognized",
            contextBeforeInput: "Please recognized"
        )

        XCTAssertTrue(
            observed.consumeIfUnchanged(contextBeforeInput: "Please recognized")
        )
        XCTAssertFalse(
            observed.consumeIfUnchanged(contextBeforeInput: "Please recognized")
        )
    }

    func testObservedSuffixAlsoRequiresTheExactCurrentWord() {
        var observed = ObservedTextSuffix(maximumCharacters: 3)
        observed.observe(committedText: "one", contextBeforeInput: "prefix one")

        // The bounded suffix still matches, but the word was genuinely edited.
        XCTAssertFalse(observed.consumeIfUnchanged(contextBeforeInput: "someone"))

        observed.observe(committedText: "word", contextBeforeInput: "a word")
        observed.retainIfUnchanged(contextBeforeInput: "a words")
        XCTAssertFalse(observed.consumeIfUnchanged(contextBeforeInput: "a word"))
    }

    func testNonEnglishContextDoesNotLeakEnglishFallbackPredictions() {
        let intelligence = TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(defaults: nil)
        )

        XCTAssertEqual(
            intelligence.suggestions(
                for: "ciao ",
                languageCode: "ita",
                limit: 3
            ),
            []
        )

        for _ in 0..<2 {
            intelligence.observeCommittedText(
                "ciao bella",
                precededBy: nil,
                languageCode: "it-IT"
            )
        }
        XCTAssertEqual(
            intelligence.suggestions(
                for: "ciao ",
                languageCode: "ita",
                limit: 1
            ).map(\.text),
            ["bella"]
        )
    }

    func testISO639ThreeLetterEnglishUsesEnglishPriors() {
        let intelligence = TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(defaults: nil)
        )

        XCTAssertEqual(
            intelligence.suggestions(
                for: "see ",
                languageCode: "eng",
                limit: 2
            ).map(\.text),
            ["you", "it"]
        )
    }

    func testEnglishPersonalPredictionsNeverLeakIntoItalian() {
        let intelligence = TextIntelligence(
            personalLanguageModel: PersonalLanguageModel(defaults: nil)
        )
        for _ in 0..<2 {
            intelligence.observeCommittedText(
                "ciao hello",
                precededBy: nil,
                languageCode: "en-US"
            )
        }

        XCTAssertEqual(
            intelligence.suggestions(
                for: "ciao ",
                languageCode: "it-IT",
                limit: 3
            ),
            []
        )
        XCTAssertEqual(
            intelligence.suggestions(
                for: "ciao ",
                languageCode: "en-GB",
                limit: 1
            ).map(\.text),
            ["hello"]
        )
    }
}
