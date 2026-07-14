import BuddyGrammarKit
import CoreGraphics
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
}
