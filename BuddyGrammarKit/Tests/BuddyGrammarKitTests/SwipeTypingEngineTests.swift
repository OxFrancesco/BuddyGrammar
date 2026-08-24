import BuddyGrammarKit
import CoreGraphics
import Foundation
import XCTest

final class SwipeTypingEngineTests: XCTestCase {
    private let engine = SwipeTypingEngine()

    func testExactLetterTraceMatchesCommonWord() {
        let candidates = engine.candidates(for: Array("the"))
        XCTAssertEqual(candidates.first, "the")
    }

    func testTraceWithIntermediateKeysStillFindsWord() {
        // Swiping "hello": h → e crosses g/f/d, e → l crosses t/y/u/i/k,
        // l → o crosses nothing new.
        let trace = Array("hgfdertyuiklo")
        let candidates = engine.candidates(for: trace, limit: 5)
        XCTAssertTrue(candidates.contains("hello"), "got \(candidates)")
    }

    func testDedupedWordLettersRankWordHighly() {
        let candidates = engine.candidates(for: Array("helo"), limit: 3)
        XCTAssertTrue(candidates.contains("hello"), "got \(candidates)")
    }

    func testNoisyPathStillMatchesWord() {
        // A wobbly path for "you": y → o → u with off-center samples.
        let path: [CGPoint] = [
            CGPoint(x: 5.1, y: 0.2),   // near y
            CGPoint(x: 6.0, y: 0.15),
            CGPoint(x: 7.1, y: 0.1),
            CGPoint(x: 8.2, y: -0.1),  // near o
            CGPoint(x: 7.4, y: 0.2),
            CGPoint(x: 6.2, y: 0.1),   // near u
        ]
        let candidates = engine.candidates(forKeySpacePath: path, limit: 3)
        XCTAssertEqual(candidates.first, "you", "got \(candidates)")
    }

    func testPreviousWordContextBoostsContinuation() {
        // "thank" → "you" is a known bigram; the boost should keep "you"
        // first even with a sloppier path.
        let path: [CGPoint] = [
            CGPoint(x: 5.4, y: 0.4),
            CGPoint(x: 7.9, y: 0.3),
            CGPoint(x: 6.3, y: 0.35),
        ]
        let candidates = engine.candidates(
            forKeySpacePath: path,
            limit: 3,
            previousWord: "thank"
        )
        XCTAssertEqual(candidates.first, "you", "got \(candidates)")
    }

    func testShortTraceReturnsNothing() {
        XCTAssertTrue(engine.candidates(for: ["a"]).isEmpty)
        XCTAssertTrue(engine.candidates(for: []).isEmpty)
    }

    func testExtraWordsAreMatched() {
        let lexicon = SwipeTypingEngine(extraWords: ["buddy"])
        let candidates = lexicon.candidates(for: Array("budy"), limit: 5)
        XCTAssertTrue(candidates.contains("buddy"), "got \(candidates)")
    }

    func testEndpointMismatchIsRejected() {
        // Trace starts at q and ends at p; "the" should not appear.
        let candidates = engine.candidates(for: Array("qwertyuiop"), limit: 10)
        XCTAssertFalse(candidates.contains("the"))
    }

    func testTimedRecognitionMatchesSharedRepeatedLetterDwellContract() throws {
        let suite = try Self.loadSharedDwellSuite()

        for testCase in suite.cases {
            let expectedWord = testCase.expect.keySequence
            let collapsedWord = String(
                expectedWord.reduce(into: [Character]()) { letters, letter in
                    if letters.last != letter { letters.append(letter) }
                }
            )
            let alternate = expectedWord == collapsedWord
                ? Self.insertingDuplicate(in: expectedWord)
                : collapsedWord
            let engine = SwipeTypingEngine(
                words: [],
                languageWords: [testCase.input.languageId: [alternate, expectedWord]]
            )
            let result = engine.recognize(
                samples: testCase.input.samples.map {
                    SwipePathSample(
                        x: $0.x,
                        y: $0.y,
                        timestampMilliseconds: $0.atMilliseconds
                    )
                },
                limit: 2,
                languageCode: testCase.input.languageId
            )

            XCTAssertEqual(
                result.acceptedCandidate?.word,
                expectedWord,
                "\(testCase.id): \(result)"
            )
            XCTAssertFalse(result.abstained, "\(testCase.id): \(result)")
            XCTAssertGreaterThan(result.confidence, 0, testCase.id)
            XCTAssertGreaterThan(result.margin, 0, testCase.id)
            XCTAssertEqual(result.candidates.first?.word, expectedWord, testCase.id)
            XCTAssertTrue(
                result.candidates.dropFirst().contains(where: { $0.word == alternate }),
                "\(testCase.id): expected post-swipe alternate \(alternate), got \(result)"
            )
        }
    }

    func testTimedRecognitionAbstainsWhenTopCandidatesAreAmbiguous() {
        let engine = SwipeTypingEngine(words: ["cat", "car"])
        let result = engine.recognize(
            samples: [
                SwipePathSample(x: 2.75, y: 2, timestampMilliseconds: 0),
                SwipePathSample(x: 0.25, y: 1, timestampMilliseconds: 100),
                // Slightly favors the lower-ranked "car" geometry so the
                // frequency prior and path likelihood cancel each other.
                SwipePathSample(x: 3.20, y: 0, timestampMilliseconds: 200),
            ],
            limit: 2
        )

        XCTAssertTrue(result.abstained, "got \(result)")
        XCTAssertNil(result.acceptedCandidate)
        XCTAssertEqual(result.abstentionReason, .ambiguous)
        XCTAssertEqual(result.candidates.count, 2)
        XCTAssertLessThan(result.margin, 0.03)
    }

    func testItalianDisplaySpellingMatchesSharedRecognitionTraces() throws {
        let suite: SwipeRecognitionSuite = try Self.loadSharedSuite(
            named: "swipe-recognition.json"
        )

        for testCase in suite.cases {
            let engine = SwipeTypingEngine(
                words: [],
                languageWords: [testCase.input.languageId: testCase.input.vocabulary]
            )
            let result = engine.recognize(
                samples: testCase.input.samples.map {
                    SwipePathSample(
                        x: $0.x,
                        y: $0.y,
                        timestampMilliseconds: $0.atMilliseconds
                    )
                },
                limit: testCase.input.vocabulary.count,
                languageCode: testCase.input.languageId
            )

            XCTAssertEqual(
                result.acceptedCandidate?.word,
                testCase.expect.displayWord,
                "\(testCase.id): \(result)"
            )
            XCTAssertEqual(
                result.candidates.first?.word,
                testCase.expect.displayWord,
                testCase.id
            )
        }
    }

    func testBundledItalianLexiconIsSelectedByBaseLocale() throws {
        let engine = SwipeTypingEngine()
        let samples = try Array("parlare").enumerated().map { index, character in
            let center = try XCTUnwrap(QwertyKeyLayout.center(of: character))
            return SwipePathSample(
                point: center,
                timestampMilliseconds: Double(index * 90)
            )
        }

        let italian = engine.recognize(
            samples: samples,
            limit: 5,
            languageCode: "it-IT"
        )
        let english = engine.recognize(
            samples: samples,
            limit: 5,
            languageCode: "en-US"
        )

        XCTAssertEqual(italian.candidates.first?.word, "parlare")
        XCTAssertFalse(english.candidates.contains(where: { $0.word == "parlare" }))
    }

    private static func insertingDuplicate(in word: String) -> String {
        guard let index = word.indices.dropFirst().first else { return word }
        return String(word[..<index]) + String(word[index]) + String(word[index...])
    }

    private static func loadSharedDwellSuite() throws -> SwipeDwellSuite {
        try loadSharedSuite(named: "swipe-dwell.json")
    }

    private static func loadSharedSuite<Suite: Decodable>(named fileName: String) throws -> Suite {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryRoot
            .appendingPathComponent("shared/keyboard-contract/v1/traces")
            .appendingPathComponent(fileName)
        return try JSONDecoder().decode(
            Suite.self,
            from: Data(contentsOf: fixtureURL)
        )
    }
}

private struct SwipeRecognitionSuite: Decodable {
    let cases: [Case]

    struct Case: Decodable {
        let id: String
        let input: Input
        let expect: Expectation
    }

    struct Input: Decodable {
        let languageId: String
        let vocabulary: [String]
        let samples: [Sample]
    }

    struct Sample: Decodable {
        let atMilliseconds: Double
        let x: Double
        let y: Double
    }

    struct Expectation: Decodable {
        let displayWord: String
        let geometryKey: String
    }
}

private struct SwipeDwellSuite: Decodable {
    let cases: [Case]

    struct Case: Decodable {
        let id: String
        let input: Input
        let expect: Expectation
    }

    struct Input: Decodable {
        let languageId: String
        let samples: [Sample]
    }

    struct Sample: Decodable {
        let atMilliseconds: Double
        let x: Double
        let y: Double
    }

    struct Expectation: Decodable {
        let keySequence: String
    }
}
