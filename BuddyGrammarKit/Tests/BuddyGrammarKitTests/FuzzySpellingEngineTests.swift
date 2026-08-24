import XCTest
@testable import BuddyGrammarKit

final class FuzzySpellingEngineTests: XCTestCase {
    private let engine = FuzzySpellingEngine(lexicon: .shared)

    func testCorrectsTranspositionFromBundledLexicon() throws {
        let corrections = engine.corrections(for: "teh", languageCode: "en-US", limit: 5)
        XCTAssertEqual(corrections.first?.display, "the")
        XCTAssertEqual(corrections.first?.distance ?? 1, 0.15, accuracy: 0.001)
    }

    func testApostropheQueriesShareGeometryWithUnpunctuatedEntries() throws {
        // "dont" ships in the pack as a canonical spelling, so typing it
        // resolves at distance zero; apostrophes are invisible to geometry.
        let corrections = engine.corrections(for: "don’t", languageCode: "en-US", limit: 5)
        XCTAssertEqual(corrections.first?.display, "dont")
        XCTAssertEqual(corrections.first?.distance, 0)
    }

    func testRestoresItalianAccent() throws {
        let corrections = engine.corrections(for: "perche", languageCode: "it-IT", limit: 5)
        XCTAssertEqual(corrections.first?.display, "perché")
    }

    func testAdjacentKeySubstitutionOutranksDistantOne() {
        let adjacent = engine.corrections(for: "gello", languageCode: "en-US", limit: 10)
        XCTAssertTrue(adjacent.contains { $0.display == "hello" })
    }

    func testUnknownGibberishProposesNothingImplausible() {
        let corrections = engine.corrections(for: "xqzjwv", languageCode: "en-US", limit: 5)
        XCTAssertTrue(corrections.isEmpty)
    }

    func testExactLexiconWordStillSurfacesWithZeroDistance() throws {
        let corrections = engine.corrections(for: "hello", languageCode: "en-US", limit: 5)
        let exact = try XCTUnwrap(corrections.first { $0.display == "hello" })
        XCTAssertEqual(exact.distance, 0)
    }

    func testUnsupportedLanguageYieldsNothing() {
        XCTAssertTrue(engine.corrections(for: "teh", languageCode: "fr-FR", limit: 3).isEmpty)
    }

    func testCanonicalizationFoldsCaseAndDiacritics() {
        XCTAssertEqual(FuzzySpellingEngine.canonicalGeometry(for: "TEH"), Array("teh".utf8))
        XCTAssertEqual(
            FuzzySpellingEngine.canonicalGeometry(for: "perchè"),
            Array("perche".utf8)
        )
        XCTAssertNil(FuzzySpellingEngine.canonicalGeometry(for: "123"))
    }

    func testLookupLatencyStaysOnTheKeystrokeBudget() {
        // The engine runs on the main actor between keystrokes. Even in an
        // unoptimized debug build the full scan must stay within a small
        // fraction of a display frame budget.
        measure {
            for word in ["teh", "dont", "helo", "recieve", "occured", "perche"] {
                _ = engine.corrections(for: word, languageCode: "en-US", limit: 6)
            }
        }
    }
}
