import BuddyGrammarKit
import XCTest

final class TapWordDecoderTests: XCTestCase {
    func testAmbiguousFinalTapDecodesHomAsHome() throws {
        let taps = [
            TapWordLatticeTap(literalKey: "h", resolvedKey: "h", candidates: [.init(key: "h", confidence: 1)]),
            TapWordLatticeTap(literalKey: "o", resolvedKey: "o", candidates: [.init(key: "o", confidence: 1)]),
            TapWordLatticeTap(literalKey: "m", resolvedKey: "m", candidates: [.init(key: "m", confidence: 1)]),
            TapWordLatticeTap(
                literalKey: "r",
                resolvedKey: "r",
                candidates: [
                    .init(key: "r", confidence: 0.52),
                    .init(key: "e", confidence: 0.48),
                ]
            ),
        ]

        let result = TapWordDecoder().decode(
            taps,
            languageCode: "en-US"
        )

        XCTAssertEqual(result.candidates.first?.word, "home")
        XCTAssertEqual(result.literalWord, "homr")
        XCTAssertEqual(result.resolvedWord, "homr")
        XCTAssertTrue(result.candidates.contains { $0.word == "homr" })
        XCTAssertGreaterThan(result.margin, 0)
    }

    func testLiteralProperNameAndResolvedPathAlwaysSurviveRanking() {
        let literal = "Francescp"
        let taps = literal.enumerated().map { index, character in
            if index == literal.count - 1 {
                return TapWordLatticeTap(
                    literalKey: character,
                    resolvedKey: "o",
                    candidates: [
                        .init(key: "o", confidence: 0.99),
                        .init(key: "p", confidence: 0.01),
                    ]
                )
            }
            return TapWordLatticeTap(
                literalKey: character,
                resolvedKey: character,
                candidates: [.init(key: character, confidence: 1)]
            )
        }

        let result = TapWordDecoder().decode(
            taps,
            languageCode: "en",
            limit: 2
        )

        XCTAssertEqual(result.literalWord, "Francescp")
        XCTAssertEqual(result.resolvedWord, "Francesco")
        XCTAssertTrue(result.candidates.contains {
            $0.word == "Francescp" && $0.isLiteralPath
        })
        XCTAssertTrue(result.candidates.contains {
            $0.word == "Francesco" && $0.isResolvedPath
        })
    }

    func testLiteralOnlyTapsRemainUnchanged() {
        let result = TapWordDecoder().decode(
            literalTaps(for: "cat"),
            languageCode: "en"
        )

        XCTAssertEqual(result.literalWord, "cat")
        XCTAssertEqual(result.resolvedWord, "cat")
        XCTAssertEqual(result.candidates.map(\.word), ["cat"])
        XCTAssertEqual(result.candidates.first?.confidence, 1)
        XCTAssertEqual(result.margin, 1)
    }

    func testMalformedAndOversizedLatticesFailClosedWithinBounds() {
        let decoder = TapWordDecoder()
        let oversized = Array(
            repeating: literalTaps(for: "a")[0],
            count: TapWordDecoder.maximumTaps + 1
        )
        XCTAssertTrue(decoder.decode(oversized).candidates.isEmpty)

        let malformed = [
            TapWordLatticeTap(
                literalKey: "a",
                resolvedKey: "p",
                candidates: [
                    .init(key: "p", confidence: 0.99),
                    .init(key: "a", confidence: .nan),
                ]
            ),
        ]
        let fallback = decoder.decode(malformed, languageCode: "en")
        XCTAssertEqual(fallback.candidates.map(\.word), ["a"])

        let crowdedTap = TapWordLatticeTap(
            literalKey: "g",
            resolvedKey: "g",
            candidates: ["g", "f", "h", "t", "y", "v", "b"].map {
                TypingCandidate(key: $0, confidence: 1)
            }
        )
        let bounded = decoder.decode(
            Array(repeating: crowdedTap, count: 4),
            limit: 999
        )
        XCTAssertLessThanOrEqual(
            bounded.candidates.count,
            TapWordDecoder.maximumResults
        )
        XCTAssertTrue(bounded.candidates.allSatisfy { $0.word.count == 4 })
    }

    func testPreviousWordContextRaisesAContinuationScore() throws {
        let taps = [
            literalTaps(for: "b")[0],
            literalTaps(for: "a")[0],
            literalTaps(for: "c")[0],
            TapWordLatticeTap(
                literalKey: "j",
                resolvedKey: "j",
                candidates: [
                    .init(key: "j", confidence: 0.52),
                    .init(key: "k", confidence: 0.48),
                ]
            ),
        ]
        let decoder = TapWordDecoder()

        let withoutContext = decoder.decode(taps, languageCode: "en")
        let withContext = decoder.decode(
            taps,
            previousWord: "come",
            languageCode: "en"
        )
        let plainBack = try XCTUnwrap(
            withoutContext.candidates.first { $0.word == "back" }
        )
        let contextualBack = try XCTUnwrap(
            withContext.candidates.first { $0.word == "back" }
        )

        XCTAssertGreaterThan(contextualBack.score, plainBack.score)
    }

    func testIdenticalInputProducesIdenticalRankingAndMargin() {
        let taps = [
            literalTaps(for: "b")[0],
            literalTaps(for: "a")[0],
            literalTaps(for: "c")[0],
            TapWordLatticeTap(
                literalKey: "j",
                resolvedKey: "k",
                candidates: [
                    .init(key: "j", confidence: 0.5),
                    .init(key: "k", confidence: 0.5),
                ]
            ),
        ]
        let decoder = TapWordDecoder()

        let first = decoder.decode(
            taps,
            previousWord: "come",
            languageCode: "en-US"
        )
        let second = decoder.decode(
            taps,
            previousWord: "come",
            languageCode: "en-US"
        )

        XCTAssertEqual(first, second)
    }

    private func literalTaps(for word: String) -> [TapWordLatticeTap] {
        word.map { character in
            TapWordLatticeTap(
                literalKey: character,
                resolvedKey: character,
                candidates: [.init(key: character, confidence: 1)]
            )
        }
    }
}
