import BuddyGrammarKit
import XCTest

final class TypingIntelligenceTests: XCTestCase {
    func testLiteralPolicyAlwaysReturnsTheLiteralKey() {
        let intelligence = TypingIntelligence(policy: .literal)
        let tap = TouchSample(x: 2.5, y: 0, literalKey: "r", timestamp: 10)

        let decision = intelligence.resolve(
            tap: tap,
            context: TypingContext(rawText: "hom", languageCode: "en")
        )

        XCTAssertEqual(decision.key, "r")
        XCTAssertEqual(decision.candidates, [TypingCandidate(key: "r", confidence: 1)])
        XCTAssertEqual(decision.confidence, 1)
        XCTAssertFalse(decision.adapted)
        XCTAssertEqual(decision.receipt.tap, tap)
        XCTAssertEqual(decision.receipt.policy, .literal)
    }

    func testMalformedTouchAndUnsupportedKeyFallBackToLiteral() {
        let intelligence = TypingIntelligence(policy: .personalizedLearning)
        let context = TypingContext(rawText: "anything", languageCode: "en")

        let malformed = intelligence.resolve(
            tap: TouchSample(x: .nan, y: 0, literalKey: "e", timestamp: 11),
            context: context
        )
        let unsupported = intelligence.resolve(
            tap: TouchSample(x: 1, y: 1, literalKey: ".", timestamp: 12),
            context: context
        )

        XCTAssertEqual(malformed.key, "e")
        XCTAssertEqual(unsupported.key, ".")
        XCTAssertEqual(unsupported.candidates.map(\.key), ["."])
    }

    func testEnglishWordPrefixExpandsTheLikelyAdjacentKey() {
        let intelligence = TypingIntelligence(policy: .generic)
        let decision = intelligence.resolve(
            tap: TouchSample(x: 2.5, y: 0, literalKey: "r", timestamp: 20),
            context: TypingContext(rawText: "hom", languageCode: "en-US")
        )

        XCTAssertEqual(decision.key, "e")
        XCTAssertTrue(decision.adapted)
        XCTAssertEqual(decision.candidates.first?.key, "e")
        XCTAssertTrue(decision.candidates.contains { $0.key == "r" })
        XCTAssertTrue(
            decision.candidates.allSatisfy {
                $0.key == "r"
                    || QwertyKeyLayout.distance("r", $0.key)
                        <= QwertyKeyLayout.neighborDistance
            }
        )
    }

    func testExplicitPracticeOutcomeLearnsOnlyAggregateTouchOffset() throws {
        var intelligence = TypingIntelligence(
            profile: TypingProfile(),
            policy: .practice
        )
        let decision = intelligence.resolve(
            tap: TouchSample(x: 2.4, y: 0.1, literalKey: "e", timestamp: 30),
            context: TypingContext(
                rawText: "private words that must never be persisted",
                languageCode: "en"
            )
        )

        intelligence.observe(
            .positive(
                receipt: decision.receipt,
                intendedKey: "e",
                source: .practice
            )
        )

        let snapshot = intelligence.snapshot
        let aggregate = try XCTUnwrap(snapshot.keyOffsets["e"])
        XCTAssertEqual(snapshot.explicitObservationCount, 1)
        XCTAssertEqual(aggregate.sampleCount, 1)
        XCTAssertEqual(aggregate.meanX, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(aggregate.meanY, 0.1, accuracy: 0.000_001)

        let encoded = try JSONEncoder().encode(snapshot)
        let roundTrip = try JSONDecoder().decode(TypingProfile.self, from: encoded)
        XCTAssertEqual(roundTrip, snapshot)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("private words"))
    }

    func testPersonalizedOffsetsCanResolveTheSameTapDifferentlyFromGeneric() {
        var trainer = TypingIntelligence(policy: .practice)
        for index in 0..<24 {
            let decision = trainer.resolve(
                tap: TouchSample(
                    x: 2.4,
                    y: 0,
                    literalKey: "e",
                    timestamp: TimeInterval(index)
                ),
                context: TypingContext(rawText: "", languageCode: "en")
            )
            trainer.observe(
                .positive(
                    receipt: decision.receipt,
                    intendedKey: "e",
                    source: .practice
                )
            )
        }

        let tap = TouchSample(x: 2.62, y: 0, literalKey: "r", timestamp: 40)
        let context = TypingContext(rawText: "", languageCode: "en")
        let generic = TypingIntelligence(policy: .generic)
        let personalized = TypingIntelligence(
            profile: trainer.snapshot,
            policy: .personalizedReadOnly
        )

        XCTAssertEqual(generic.resolve(tap: tap, context: context).key, "r")
        XCTAssertEqual(personalized.resolve(tap: tap, context: context).key, "e")
    }

    func testCentralLiteralAnchorCannotBeOverriddenByLanguage() {
        let intelligence = TypingIntelligence(policy: .generic)
        let decision = intelligence.resolve(
            tap: TouchSample(x: 3.1, y: 0, literalKey: "r", timestamp: 50),
            context: TypingContext(rawText: "hom", languageCode: "en")
        )

        XCTAssertEqual(decision.key, "r")
        XCTAssertFalse(decision.adapted)
        XCTAssertEqual(decision.candidates.map(\.key), ["r"])
    }

    func testWeakOrEqualLanguageEvidencePreservesLiteral() {
        let intelligence = TypingIntelligence(policy: .generic)
        let decision = intelligence.resolve(
            tap: TouchSample(x: 2.5, y: 0, literalKey: "r", timestamp: 51),
            context: TypingContext(rawText: "zz", languageCode: "en")
        )

        XCTAssertEqual(decision.key, "r")
        XCTAssertFalse(decision.adapted)
    }

    func testNonEnglishContextNeverUsesEnglishWordPrior() {
        let intelligence = TypingIntelligence(policy: .generic)
        let decision = intelligence.resolve(
            tap: TouchSample(x: 2.5, y: 0, literalKey: "r", timestamp: 52),
            context: TypingContext(rawText: "hom", languageCode: "it-IT")
        )

        XCTAssertEqual(decision.key, "r")
        XCTAssertFalse(decision.adapted)
    }

    func testOnlyLearningPoliciesAndExplicitSourcesMutateProfile() {
        let tap = TouchSample(x: 2.5, y: 0, literalKey: "r", timestamp: 60)
        let context = TypingContext(rawText: "", languageCode: "en")

        var generic = TypingIntelligence(policy: .generic)
        let genericDecision = generic.resolve(tap: tap, context: context)
        generic.observe(
            .positive(
                receipt: genericDecision.receipt,
                intendedKey: "e",
                source: .practice
            )
        )
        XCTAssertEqual(generic.snapshot, TypingProfile())

        var learning = TypingIntelligence(policy: .personalizedLearning)
        let learningDecision = learning.resolve(tap: tap, context: context)
        learning.observe(
            .positive(
                receipt: learningDecision.receipt,
                intendedKey: learningDecision.key,
                source: .decoder
            )
        )
        XCTAssertEqual(learning.snapshot, TypingProfile())

        learning.observe(
            .rejection(
                receipt: learningDecision.receipt,
                correctedKey: "e",
                source: .retype
            )
        )
        XCTAssertEqual(learning.snapshot.explicitObservationCount, 1)
        XCTAssertEqual(learning.snapshot.rejectionCount, 1)
        XCTAssertEqual(learning.snapshot.confusions["r>e"], 1)
    }

    func testContextRetainsOnlyABoundedSuffix() {
        let context = TypingContext(
            rawText: String(repeating: "x", count: 200) + "ending",
            languageCode: "EN_us"
        )

        XCTAssertEqual(context.rawText.count, TypingContext.maximumCharacterCount)
        XCTAssertTrue(context.rawText.hasSuffix("ending"))
        XCTAssertEqual(context.languageCode, "en_us")
    }
}
