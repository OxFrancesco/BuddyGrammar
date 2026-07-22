import Foundation
import XCTest
@testable import BuddyGrammarKit

final class KeyboardContractConformanceTests: XCTestCase {
    func testCapabilityPolicyReplaysBundledSharedContract() throws {
        let suite = try ContractFixture.load(
            "capability-policy",
            as: ContractCapabilitySuite.self
        )
        let catalog = try KeyboardCatalog.bundled()
        XCTAssertEqual(suite.schemaVersion, 1)
        XCTAssertEqual(suite.catalogRevision, catalog.catalogRevision)

        for testCase in suite.cases {
            let fieldKind = try testCase.input.fieldKind.editorFieldKind()
            let capabilities = EditorCapabilityPolicy.evaluate(
                traits: EditorFieldTraits(
                    kind: fieldKind,
                    isSecure: testCase.input.secure,
                    suggestionsDisabled: testCase.input.noSuggestions,
                    personalizedLearningDisabled:
                        testCase.input.noPersonalizedLearning
                ),
                environment: EditorCapabilityEnvironment(
                    cloudTransportAvailable:
                        testCase.input.cloudTransportAvailable,
                    hasCloudProcessingConsent:
                        testCase.input.cloudProcessingConsent,
                    platformVoiceAvailable:
                        testCase.input.platformVoiceAvailable,
                    editorCanMoveCursor:
                        testCase.input.editorCanMoveCursor,
                    sharedContainerAvailable: true
                )
            )
            let catalogKind = capabilities.presentationFieldKind.catalogFieldKind
            let presentation = catalog.presentation(
                for: catalogKind,
                localeIdentifier: "en"
            )
            let layoutVariant = presentation.layout.fieldVariants.first {
                $0.fieldKinds.contains(presentation.fieldKind.rawValue)
            }?.id

            XCTAssertEqual(
                layoutVariant,
                Optional(testCase.expect.layoutVariant),
                testCase.id
            )
            XCTAssertEqual(
                capabilities.suggestions.isAllowed,
                testCase.expect.canSuggest,
                testCase.id
            )
            XCTAssertEqual(
                capabilities.personalizedLearning.isAllowed,
                testCase.expect.canLearn,
                testCase.id
            )
            XCTAssertEqual(
                capabilities.automaticCorrection.isAllowed,
                testCase.expect.canAutoCorrect,
                testCase.id
            )
            XCTAssertEqual(
                capabilities.swipeTyping.isAllowed,
                testCase.expect.canSwipe,
                testCase.id
            )
            XCTAssertEqual(
                capabilities.readContext.isAllowed,
                testCase.expect.canReadContext,
                testCase.id
            )
            XCTAssertEqual(
                capabilities.useComposition.isAllowed,
                testCase.expect.canUseComposition,
                testCase.id
            )
            XCTAssertEqual(
                capabilities.cursorMovement.isAllowed,
                testCase.expect.canMoveCursor,
                testCase.id
            )
            XCTAssertEqual(
                contractCode(for: capabilities.cloudCorrection),
                testCase.expect.buddyFix,
                testCase.id
            )
            XCTAssertEqual(
                contractCode(for: capabilities.platformVoice),
                testCase.expect.platformVoice,
                testCase.id
            )
        }
    }

    @MainActor
    func testCorrectionReceiptsReplayBundledSharedContract() throws {
        let suite = try ContractFixture.load(
            "correction-receipts",
            as: ContractCorrectionSuite.self
        )
        XCTAssertEqual(suite.schemaVersion, 1)
        XCTAssertEqual(
            suite.catalogRevision,
            try KeyboardCatalog.bundled().catalogRevision
        )

        for testCase in suite.cases {
            let actual = CorrectionContractDriver.replay(
                input: testCase.input,
                events: testCase.events
            )
            XCTAssertEqual(actual.text, testCase.expect.text, testCase.id)
            XCTAssertEqual(
                actual.fieldEpoch,
                testCase.expect.fieldEpoch,
                testCase.id
            )
            XCTAssertEqual(
                actual.activeReceipt,
                testCase.expect.activeReceipt,
                testCase.id
            )
            XCTAssertEqual(
                actual.receiptMode,
                testCase.expect.receiptMode,
                testCase.id
            )
            XCTAssertEqual(
                actual.receiptSource,
                testCase.expect.receiptSource,
                testCase.id
            )
            XCTAssertEqual(
                actual.pendingLearning,
                testCase.expect.pendingLearning,
                testCase.id
            )
            XCTAssertEqual(
                actual.acceptedLearning,
                testCase.expect.acceptedLearning,
                testCase.id
            )
            XCTAssertEqual(
                actual.rejectedSources,
                testCase.expect.rejectedSources,
                testCase.id
            )
            XCTAssertEqual(
                actual.ignoredEvents,
                testCase.expect.ignoredEvents,
                testCase.id
            )
        }
    }

    func testInteractionRoutingReplaysBundledSharedContract() throws {
        let suite = try ContractFixture.load(
            "interaction-routing",
            as: ContractInteractionSuite.self
        )
        XCTAssertEqual(suite.schemaVersion, 1)
        XCTAssertEqual(
            suite.catalogRevision,
            try KeyboardCatalog.bundled().catalogRevision
        )

        for testCase in suite.cases {
            let actual = try SwiftInteractionTraceReplayer.replay(
                configuration: suite.configuration,
                events: testCase.events,
                caseID: testCase.id
            )
            XCTAssertEqual(actual, testCase.expect, testCase.id)
        }
    }

    func testTimedSwipeRecognitionReplaysBundledSharedDwellContract() throws {
        let suite = try ContractFixture.load(
            "swipe-dwell",
            as: ContractSwipeSuite.self
        )
        XCTAssertEqual(suite.schemaVersion, 1)
        XCTAssertEqual(
            suite.catalogRevision,
            try KeyboardCatalog.bundled().catalogRevision
        )

        for testCase in suite.cases {
            let expectedWord = testCase.expect.keySequence
            let collapsedWord = collapsedRepeatedRuns(in: expectedWord)
            let alternate = expectedWord == collapsedWord
                ? insertingDuplicate(in: expectedWord)
                : collapsedWord
            let engine = SwipeTypingEngine(
                words: [],
                languageWords: [
                    testCase.input.languageId: [alternate, expectedWord],
                ]
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
            XCTAssertEqual(
                result.acceptedCandidate.map { repeatedRuns(in: $0.word) },
                Optional(testCase.expect.repeatedRuns),
                testCase.id
            )
            XCTAssertEqual(result.candidates.first?.word, expectedWord, testCase.id)
            XCTAssertTrue(
                result.candidates.dropFirst().contains { $0.word == alternate },
                "\(testCase.id): expected alternate \(alternate), got \(result)"
            )
            XCTAssertFalse(result.abstained, "\(testCase.id): \(result)")
        }
    }

    func testItalianSwipeRecognitionReplaysBundledSharedDisplayContract() throws {
        let suite = try ContractFixture.load(
            "swipe-recognition",
            as: ContractSwipeRecognitionSuite.self
        )
        XCTAssertEqual(suite.schemaVersion, 1)
        XCTAssertEqual(
            suite.catalogRevision,
            try KeyboardCatalog.bundled().catalogRevision
        )

        for testCase in suite.cases {
            let engine = SwipeTypingEngine(
                words: [],
                languageWords: [
                    testCase.input.languageId: testCase.input.vocabulary,
                ]
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
            XCTAssertEqual(
                SwipeWordNormalizer.normalize(testCase.expect.displayWord)?.geometry,
                testCase.expect.geometryKey,
                testCase.id
            )
            XCTAssertFalse(result.abstained, "\(testCase.id): \(result)")
        }
    }

    func testTapDecoderReplaysBundledSharedLanguageContract() throws {
        let suite = try ContractFixture.load(
            "tap-decoding",
            as: ContractTapDecodingSuite.self
        )
        XCTAssertEqual(suite.schemaVersion, 1)
        XCTAssertEqual(
            suite.catalogRevision,
            try KeyboardCatalog.bundled().catalogRevision
        )
        let decoder = TapWordDecoder()

        for testCase in suite.cases {
            let result = decoder.decode(
                testCase.input.taps.map { tap in
                    TapWordLatticeTap(
                        literalKey: Character(tap.literalKey),
                        resolvedKey: Character(tap.resolvedKey),
                        candidates: tap.candidates.map {
                            TypingCandidate(
                                key: Character($0.key),
                                confidence: $0.confidence
                            )
                        }
                    )
                },
                languageCode: testCase.input.languageId,
                limit: 5
            )
            let candidateWords = result.candidates.map(\.word)

            XCTAssertEqual(result.literalWord, testCase.expect.literalWord, testCase.id)
            XCTAssertEqual(result.resolvedWord, testCase.expect.resolvedWord, testCase.id)
            XCTAssertEqual(candidateWords.first, testCase.expect.topWord, testCase.id)
            let policy = try XCTUnwrap(
                TapWordAcceptancePolicy(rawValue: testCase.input.policy),
                testCase.id
            )
            XCTAssertEqual(
                policy.acceptedCandidate(from: result)?.word,
                testCase.expect.acceptedWord,
                testCase.id
            )
            for word in testCase.expect.containsWords {
                XCTAssertTrue(candidateWords.contains(word), "\(testCase.id): missing \(word) in \(candidateWords)")
            }
            for word in testCase.expect.excludesWords {
                XCTAssertFalse(candidateWords.contains(word), "\(testCase.id): unexpected \(word) in \(candidateWords)")
            }
        }
    }

    private func contractCode(for access: EditorFeatureAccess) -> String {
        switch access {
        case .allowed:
            "allowed"
        case .denied(let reason):
            switch reason {
            case .sensitiveField:
                "denied.sensitive-field"
            case .structuredField:
                "denied.structured-field"
            case .codeField:
                "denied.code-field"
            case .suggestionsDisabled:
                "denied.editor-no-suggestions"
            case .personalizedLearningDisabled:
                "denied.personalized-learning-disabled"
            case .cloudTransportUnavailable:
                "denied.cloud-transport-unavailable"
            case .cloudProcessingConsentRequired:
                "denied.cloud-consent-required"
            case .platformVoiceUnavailable:
                "denied.platform-voice-unavailable"
            case .cursorMovementUnavailable:
                "denied.cursor-unavailable"
            case .sharedContainerUnavailable:
                "denied.shared-container-unavailable"
            case .contextReadUnavailable:
                "denied.context-unavailable"
            case .compositionUnavailable:
                "denied.composition-unavailable"
            }
        }
    }

    private func collapsedRepeatedRuns(in word: String) -> String {
        String(word.reduce(into: [Character]()) { result, character in
            if result.last != character { result.append(character) }
        })
    }

    private func repeatedRuns(in word: String) -> [String] {
        var result: [String] = []
        var previous: Character?
        var count = 0
        for character in word {
            if character == previous {
                count += 1
            } else {
                if let previous, count > 1 { result.append(String(previous)) }
                previous = character
                count = 1
            }
        }
        if let previous, count > 1 { result.append(String(previous)) }
        return result
    }

    private func insertingDuplicate(in word: String) -> String {
        var characters = Array(word)
        guard characters.count >= 2 else { return word }
        characters.insert(characters[1], at: 1)
        return String(characters)
    }
}

private enum ContractFixture {
    static func load<Value: Decodable>(
        _ name: String,
        as type: Value.Type
    ) throws -> Value {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "KeyboardContract"
        ) else {
            throw ContractFixtureError.missing(name)
        }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}

private enum ContractFixtureError: Error {
    case missing(String)
    case unknownFieldKind(String)
}

private extension String {
    func editorFieldKind() throws -> EditorFieldKind {
        switch self {
        case "text": .plainText
        case "multiline": .multiline
        case "literal": .literal
        case "search": .search
        case "email": .emailAddress
        case "url": .url
        case "name": .personName
        case "phone": .phoneNumber
        case "number": .number
        case "decimal": .decimal
        case "datetime": .dateTime
        case "oneTimeCode": .oneTimeCode
        case "password": .password
        case "code": .code
        default: throw ContractFixtureError.unknownFieldKind(self)
        }
    }
}

private struct ContractCapabilitySuite: Decodable {
    let schemaVersion: Int
    let catalogRevision: String
    let cases: [Case]

    struct Case: Decodable {
        let id: String
        let input: Input
        let expect: Expectation
    }

    struct Input: Decodable {
        let fieldKind: String
        let secure: Bool
        let noSuggestions: Bool
        let noPersonalizedLearning: Bool
        let cloudProcessingConsent: Bool
        let cloudTransportAvailable: Bool
        let platformVoiceAvailable: Bool
        let editorCanMoveCursor: Bool
    }

    struct Expectation: Decodable {
        let layoutVariant: String
        let canSuggest: Bool
        let canLearn: Bool
        let canAutoCorrect: Bool
        let canSwipe: Bool
        let canReadContext: Bool
        let canUseComposition: Bool
        let canMoveCursor: Bool
        let buddyFix: String
        let platformVoice: String
    }
}

private struct ContractCorrectionSuite: Decodable {
    let schemaVersion: Int
    let catalogRevision: String
    let cases: [Case]

    struct Case: Decodable {
        let id: String
        let input: Input
        let events: [Event]
        let expect: Expectation
    }

    struct Input: Decodable {
        let initialText: String
        let initialFieldEpoch: Int
    }

    struct Event: Decodable {
        let kind: String
        let atMilliseconds: Double
        let source: String?
        let original: String?
        let replacement: String?
        let boundary: String?
        let text: String?
        let receiptLifetimeMilliseconds: Double?
        let capturedFieldEpoch: Int?
    }

    struct Expectation: Decodable {
        let text: String
        let fieldEpoch: Int
        let activeReceipt: Bool
        let receiptMode: String?
        let receiptSource: String?
        let pendingLearning: Bool
        let acceptedLearning: [String]
        let rejectedSources: [String]
        let ignoredEvents: Int
    }
}

private struct ContractInteractionSuite: Decodable {
    let schemaVersion: Int
    let catalogRevision: String
    let configuration: Configuration
    let cases: [Case]

    struct Configuration: Decodable {
        let longPressDelayMilliseconds: Double
        let swipeDistance: Double
        let alternateStep: Double
        let cursorActivationMilliseconds: Double
        let cursorActivationDistance: Double
        let cursorStep: Double
        let deleteRepeatDelayMilliseconds: Double
        let deleteRepeatIntervalMilliseconds: Double

        var native: KeyboardInteractionRouter.Configuration {
            KeyboardInteractionRouter.Configuration(
                longPressDelay: longPressDelayMilliseconds / 1_000,
                swipeDistance: swipeDistance,
                alternateStep: alternateStep,
                cursorActivationDistance: cursorActivationDistance,
                cursorActivationDelay: cursorActivationMilliseconds / 1_000,
                cursorStep: cursorStep,
                deleteRepeatDelay: deleteRepeatDelayMilliseconds / 1_000,
                deleteRepeatInterval: deleteRepeatIntervalMilliseconds / 1_000,
                minimumDeleteRepeatInterval:
                    deleteRepeatIntervalMilliseconds / 1_000,
                wordDeleteAfterRepeats: .max
            )
        }
    }

    struct Case: Decodable {
        let id: String
        let events: [Event]
        let expect: Outcome
    }

    struct Event: Decodable {
        let kind: String
        let atMilliseconds: Double
        let literal: String?
        let alternates: [String]?
        let x: Double?
        let y: Double?
        let deadlineKind: String?

        var point: InteractionPoint {
            InteractionPoint(x: x ?? 0, y: y ?? 0)
        }
    }

    struct Outcome: Decodable, Equatable {
        let committedText: [String]
        let deleteBackwardCount: Int
        let deleteWordCount: Int
        let cursorDeltas: [Int]
        let swipePhases: [String]
        let keyFeedbackCount: Int
        let selectionFeedbackCount: Int
        let alternateSelections: [Int]
        let hideAlternatesCount: Int
        let settled: Bool
    }
}

private struct SwiftInteractionTraceReplayer {
    private var router: KeyboardInteractionRouter
    private var projector = InteractionEffectProjector()
    private var scheduled: [String: KeyboardInteractionDeadline] = [:]

    private init(configuration: ContractInteractionSuite.Configuration) {
        router = KeyboardInteractionRouter(configuration: configuration.native)
    }

    static func replay(
        configuration: ContractInteractionSuite.Configuration,
        events: [ContractInteractionSuite.Event],
        caseID: String
    ) throws -> ContractInteractionSuite.Outcome {
        var replayer = Self(configuration: configuration)
        for event in events {
            try replayer.consume(event, caseID: caseID)
        }
        return replayer.projector.outcome
    }

    private mutating func consume(
        _ event: ContractInteractionSuite.Event,
        caseID: String
    ) throws {
        let time = event.atMilliseconds / 1_000
        let input: KeyboardInteractionInput
        switch event.kind {
        case "pressKey":
            guard let literal = event.literal else {
                throw ContractInteractionError.missingLiteral(caseID)
            }
            input = .press(
                target: .key(literal, alternates: event.alternates ?? []),
                at: event.point,
                time: time
            )
        case "pressSpace":
            input = .press(target: .space, at: event.point, time: time)
        case "pressDelete":
            input = .press(target: .delete, at: event.point, time: time)
        case "move":
            input = .move(to: event.point, time: time)
        case "release":
            input = .release(at: event.point, time: time)
        case "cancel":
            input = .cancel
        case "fireScheduled":
            guard let rawKind = event.deadlineKind else {
                throw ContractInteractionError.unknownDeadline(caseID, nil)
            }
            let kind = try deadlineKind(rawKind, caseID: caseID)
            guard let deadline = scheduled.removeValue(forKey: rawKind) else {
                throw ContractInteractionError.missingDeadline(caseID, event.deadlineKind)
            }
            XCTAssertEqual(deadline.kind, kind, caseID)
            XCTAssertEqual(
                deadline.dueTime,
                time,
                accuracy: 0.000_001,
                "\(caseID): \(event.deadlineKind ?? "unknown") deadline"
            )
            input = .deadline(deadline)
        default:
            throw ContractInteractionError.unknownEvent(caseID, event.kind)
        }

        consume(router.handle(input))
    }

    private mutating func consume(_ effects: [KeyboardInteractionEffect]) {
        projector.consume(effects)
        for effect in effects {
            guard case let .schedule(deadline) = effect else { continue }
            scheduled[deadlineKey(deadline.kind)] = deadline
        }
    }

    private func deadlineKey(_ kind: KeyboardInteractionDeadline.Kind) -> String {
        switch kind {
        case .longPress: "longPress"
        case .cursorActivation: "cursorActivation"
        case .deleteRepeat: "deleteRepeat"
        }
    }

    private func deadlineKind(
        _ raw: String?,
        caseID: String
    ) throws -> KeyboardInteractionDeadline.Kind {
        switch raw {
        case "longPress": .longPress
        case "cursorActivation": .cursorActivation
        case "deleteRepeat": .deleteRepeat
        default: throw ContractInteractionError.unknownDeadline(caseID, raw)
        }
    }
}

private struct InteractionEffectProjector {
    private var committedText: [String] = []
    private var deleteBackwardCount = 0
    private var deleteWordCount = 0
    private var cursorDeltas: [Int] = []
    private var swipePhases: [String] = []
    private var keyFeedbackCount = 0
    private var selectionFeedbackCount = 0
    private var alternateSelections: [Int] = []
    private var hideAlternatesCount = 0
    private var isPressed = false
    private var previewVisible = false
    private var alternatesVisible = false

    mutating func consume(_ effects: [KeyboardInteractionEffect]) {
        for effect in effects {
            switch effect {
            case .pressed(let target):
                isPressed = target != nil
            case .preview(let text):
                previewVisible = text != nil
            case .showAlternates(_, let selectedIndex):
                alternatesVisible = true
                alternateSelections.append(selectedIndex)
            case .hideAlternates:
                alternatesVisible = false
                hideAlternatesCount += 1
            case .commitText(let text):
                committedText.append(text)
            case .deleteBackward:
                deleteBackwardCount += 1
            case .deleteWord:
                deleteWordCount += 1
            case .moveCursor(let delta):
                cursorDeltas.append(delta)
            case .swipeBegan:
                swipePhases.append("began")
            case .swipeMoved:
                swipePhases.append("moved")
            case .swipeEnded:
                swipePhases.append("ended")
            case .feedback(.key):
                keyFeedbackCount += 1
            case .feedback(.selection):
                selectionFeedbackCount += 1
            case .schedule:
                break
            }
        }
    }

    var outcome: ContractInteractionSuite.Outcome {
        return ContractInteractionSuite.Outcome(
            committedText: committedText,
            deleteBackwardCount: deleteBackwardCount,
            deleteWordCount: deleteWordCount,
            cursorDeltas: cursorDeltas,
            swipePhases: swipePhases,
            keyFeedbackCount: keyFeedbackCount,
            selectionFeedbackCount: selectionFeedbackCount,
            alternateSelections: alternateSelections,
            hideAlternatesCount: hideAlternatesCount,
            settled: !isPressed && !previewVisible && !alternatesVisible
        )
    }
}

private enum ContractInteractionError: Error {
    case missingLiteral(String)
    case missingDeadline(String, String?)
    case unknownDeadline(String, String?)
    case unknownEvent(String, String)
}

private struct ContractCorrectionState: Equatable {
    let text: String
    let fieldEpoch: Int
    let activeReceipt: Bool
    let receiptMode: String?
    let receiptSource: String?
    let pendingLearning: Bool
    let acceptedLearning: [String]
    let rejectedSources: [String]
    let ignoredEvents: Int
}

/// Maps JSON contract events into the same production session interface used
/// by the keyboard. Lifecycle behavior remains inside that module.
@MainActor
private struct CorrectionContractDriver {
    private let editor: CorrectionCompositionValueEditor
    private var session: CorrectionCompositionSession
    private var acceptedLearning: [String] = []
    private var rejectedSources: [String] = []
    private var ignoredEvents = 0

    static func replay(
        input: ContractCorrectionSuite.Input,
        events: [ContractCorrectionSuite.Event]
    ) -> ContractCorrectionState {
        var driver = Self(
            editor: CorrectionCompositionValueEditor(text: input.initialText),
            session: CorrectionCompositionSession(
                initialFieldEpoch: input.initialFieldEpoch,
                fieldIdentifier: "field-\(input.initialFieldEpoch)"
            )
        )
        events.forEach { driver.consume($0) }
        return driver.state
    }

    private var state: ContractCorrectionState {
        let snapshot = session.snapshot
        return ContractCorrectionState(
            text: editor.text,
            fieldEpoch: snapshot.fieldEpoch,
            activeReceipt: snapshot.hasActiveReceipt,
            receiptMode: snapshot.receiptMode?.rawValue,
            receiptSource: snapshot.receiptSource,
            pendingLearning: snapshot.hasPendingLearning,
            acceptedLearning: acceptedLearning,
            rejectedSources: rejectedSources,
            ignoredEvents: ignoredEvents
        )
    }

    private mutating func consume(_ event: ContractCorrectionSuite.Event) {
        switch event.kind {
        case "applyAutomatic":
            let effect = applyAutomatic(event)
            consume(effect)
        case "applyExplicit":
            let effect = applyExplicit(event)
            consume(effect)
        case "applyAsyncAutomatic":
            let effect = applyAsyncAutomatic(event)
            consume(effect)
        case "backspace":
            let effect = session.backspace(in: editor)
            consume(effect)
        case "revert":
            let effect = session.visibleRevert(in: editor)
            consume(effect)
        case "externalEdit":
            editor.replaceTextExternally(event.text ?? editor.text)
            session.externalEditObserved()
        case "changeField":
            let nextEpoch = session.snapshot.fieldEpoch + 1
            session.changeField(to: "field-\(nextEpoch)")
            editor.replaceTextExternally(event.text ?? "")
        case "advanceTime":
            let effect = session.advanceTime(
                toMilliseconds: event.atMilliseconds,
                in: editor
            )
            consume(effect)
        default:
            ignoredEvents += 1
        }
    }

    private mutating func applyAutomatic(
        _ event: ContractCorrectionSuite.Event
    ) -> CorrectionCompositionEffect {
        guard let sourceName = event.source,
              let source = automaticSource(sourceName),
              let original = event.original,
              let replacement = event.replacement else {
            return CorrectionCompositionEffect(ignored: true)
        }
        let boundary = event.boundary ?? ""
        let precedingContext = editor.text.hasSuffix(original)
            ? String(editor.text.dropLast(original.count))
            : ""
        return session.applyAutomatic(
            in: editor,
            originalText: original,
            replacementText: replacement,
            boundary: boundary,
            precedingContext: precedingContext,
            languageCode: "en",
            source: source,
            atMilliseconds: event.atMilliseconds,
            receiptLifetimeMilliseconds:
                event.receiptLifetimeMilliseconds ?? 3_000
        )
    }

    private mutating func applyAsyncAutomatic(
        _ event: ContractCorrectionSuite.Event
    ) -> CorrectionCompositionEffect {
        guard let capturedFieldEpoch = event.capturedFieldEpoch,
              let sourceName = event.source,
              let source = automaticSource(sourceName),
              let original = event.original,
              let replacement = event.replacement else {
            return CorrectionCompositionEffect(ignored: true)
        }
        let boundary = event.boundary ?? ""
        let precedingContext = editor.text.hasSuffix(original)
            ? String(editor.text.dropLast(original.count))
            : ""
        return session.applyAsyncAutomatic(
            stamp: CorrectionCompositionAsyncStamp(
                fieldEpoch: capturedFieldEpoch,
                fieldIdentifier: session.snapshot.fieldIdentifier
            ),
            in: editor,
            originalText: original,
            replacementText: replacement,
            boundary: boundary,
            precedingContext: precedingContext,
            languageCode: "en",
            source: source,
            atMilliseconds: event.atMilliseconds,
            receiptLifetimeMilliseconds:
                event.receiptLifetimeMilliseconds ?? 3_000
        )
    }

    private mutating func applyExplicit(
        _ event: ContractCorrectionSuite.Event
    ) -> CorrectionCompositionEffect {
        guard let source = event.source,
              let original = event.original,
              let replacement = event.replacement else {
            return CorrectionCompositionEffect(ignored: true)
        }
        let precedingContext = editor.text.hasSuffix(original)
            ? String(editor.text.dropLast(original.count))
            : ""
        return session.applyExplicit(
            in: editor,
            originalText: original,
            replacementText: replacement,
            source: source,
            precedingContext: precedingContext,
            languageCode: "en",
            atMilliseconds: event.atMilliseconds,
            receiptLifetimeMilliseconds:
                event.receiptLifetimeMilliseconds ?? 3_000
        )
    }

    private mutating func consume(_ effect: CorrectionCompositionEffect) {
        if effect.ignored { ignoredEvents += 1 }
        if let learning = effect.acceptedLearning {
            acceptedLearning.append(learning.text)
        }
        if let rejection = effect.rejection {
            rejectedSources.append(rejection.source)
        }
    }

    private func automaticSource(
        _ source: String
    ) -> AutomaticCorrectionSource? {
        switch source {
        case "tapLattice": .tapLattice
        case "spelling": .spelling
        case "shortcut": .shortcut
        case "swipe": .swipe
        default: nil
        }
    }
}

private struct ContractSwipeSuite: Decodable {
    let schemaVersion: Int
    let catalogRevision: String
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
        let repeatedRuns: [String]
    }
}

private struct ContractSwipeRecognitionSuite: Decodable {
    let schemaVersion: Int
    let catalogRevision: String
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

private struct ContractTapDecodingSuite: Decodable {
    let schemaVersion: Int
    let catalogRevision: String
    let cases: [Case]

    struct Case: Decodable {
        let id: String
        let input: Input
        let expect: Expectation
    }

    struct Input: Decodable {
        let languageId: String
        let policy: String
        let taps: [Tap]
    }

    struct Tap: Decodable {
        let literalKey: String
        let resolvedKey: String
        let candidates: [Candidate]
    }

    struct Candidate: Decodable {
        let key: String
        let confidence: Double
    }

    struct Expectation: Decodable {
        let literalWord: String
        let resolvedWord: String
        let topWord: String
        let acceptedWord: String?
        let containsWords: [String]
        let excludesWords: [String]
    }
}
