import BuddyGrammarKit
import XCTest

final class KeyboardInteractionRouterTests: XCTestCase {
    func testLetterAndSpaceFeedbackHappensOnPressWithoutAReleaseDuplicate() {
        var router = KeyboardInteractionRouter()

        XCTAssertEqual(
            router.handle(
                .press(target: .key("a", alternates: []), at: .zero, time: 0)
            ).last,
            .feedback(.key)
        )
        XCTAssertEqual(
            router.handle(.release(at: .zero, time: 0.1)).feedbackEffects,
            []
        )

        XCTAssertEqual(
            router.handle(.press(target: .space, at: .zero, time: 1)).last,
            .feedback(.key)
        )
        XCTAssertEqual(
            router.handle(.release(at: .zero, time: 1.1)).feedbackEffects,
            []
        )
    }

    func testTapShowsPreviewThenCommitsLiteral() {
        var router = KeyboardInteractionRouter()

        XCTAssertEqual(
            router.handle(.press(target: .key("e", alternates: []), at: .zero, time: 0)),
            [
                .pressed(.key("e", alternates: [])),
                .preview("e"),
                .feedback(.key),
            ]
        )
        XCTAssertEqual(
            router.handle(.release(at: .zero, time: 0.08)),
            [
                .commitText("e"),
                .preview(nil),
                .pressed(nil),
            ]
        )
    }

    func testLongPressChoosesAnAccentWithoutCommittingTheBaseKey() throws {
        var router = KeyboardInteractionRouter()
        let pressEffects = router.handle(
            .press(
                target: .key("e", alternates: ["é", "è", "ê"]),
                at: .zero,
                time: 1
            )
        )
        let deadline = try XCTUnwrap(pressEffects.compactMap(\.deadline).first)

        XCTAssertEqual(
            router.handle(.deadline(deadline)),
            [
                .showAlternates(["é", "è", "ê"], selectedIndex: 0),
                .feedback(.selection),
            ]
        )
        XCTAssertEqual(
            router.handle(.move(to: InteractionPoint(x: 52, y: 0), time: 1.5)),
            [.showAlternates(["é", "è", "ê"], selectedIndex: 2)]
        )
        XCTAssertEqual(
            router.handle(.release(at: InteractionPoint(x: 52, y: 0), time: 1.6)),
            [
                .commitText("ê"),
                .hideAlternates,
                .preview(nil),
                .pressed(nil),
            ]
        )
    }

    func testSpacebarDragMovesCursorAndDoesNotInsertSpace() {
        var router = KeyboardInteractionRouter()
        _ = router.handle(.press(target: .space, at: .zero, time: 2))

        XCTAssertEqual(
            router.handle(.move(to: InteractionPoint(x: 31, y: 2), time: 2.1)),
            [
                .preview(nil),
                .feedback(.selection),
                .moveCursor(2),
            ]
        )
        XCTAssertEqual(
            router.handle(.move(to: InteractionPoint(x: 47, y: 2), time: 2.15)),
            [.moveCursor(1)]
        )
        XCTAssertEqual(
            router.handle(.release(at: InteractionPoint(x: 47, y: 2), time: 2.2)),
            [.pressed(nil)]
        )
    }

    func testSpacebarHoldEntersCursorModeWithoutInsertingSpace() throws {
        var router = KeyboardInteractionRouter(
            configuration: .init(cursorActivationDelay: 0.18)
        )
        let pressEffects = router.handle(
            .press(target: .space, at: .zero, time: 10)
        )
        let deadline = try XCTUnwrap(pressEffects.compactMap(\.deadline).first)

        XCTAssertEqual(deadline.kind, .cursorActivation)
        XCTAssertEqual(
            router.handle(.deadline(deadline)),
            [.preview(nil), .feedback(.selection)]
        )
        XCTAssertEqual(
            router.handle(.release(at: .zero, time: 10.25)),
            [.pressed(nil)]
        )
    }

    func testDeleteCommitsImmediatelyThenAcceleratesCharacterRepeats() throws {
        var router = KeyboardInteractionRouter()
        var effects = router.handle(.press(target: .delete, at: .zero, time: 3))

        XCTAssertEqual(Array(effects.prefix(3)), [
            .pressed(.delete),
            .deleteBackward,
            .feedback(.key),
        ])

        var deadline = try XCTUnwrap(effects.compactMap(\.deadline).first)
        for repeatIndex in 0..<12 {
            effects = router.handle(.deadline(deadline))
            XCTAssertEqual(effects.first, .deleteBackward, "repeat \(repeatIndex)")
            deadline = try XCTUnwrap(effects.compactMap(\.deadline).first)
        }
    }

    func testSwipeSuppressesLiteralCommit() {
        var router = KeyboardInteractionRouter()
        let pressEffects = router.handle(
            .press(target: .key("h", alternates: []), at: .zero, time: 4)
        )
        XCTAssertEqual(pressEffects.feedbackEffects, [.feedback(.key)])

        XCTAssertEqual(
            router.handle(.move(to: InteractionPoint(x: 30, y: 4), time: 4.1)),
            [
                .preview(nil),
                .swipeBegan(.zero),
                .swipeMoved(InteractionPoint(x: 30, y: 4)),
            ]
        )
        XCTAssertEqual(
            router.handle(.release(at: InteractionPoint(x: 55, y: 5), time: 4.2)),
            [
                .swipeEnded(InteractionPoint(x: 55, y: 5)),
                .pressed(nil),
            ]
        )
    }

    func testSwipeDeniedAccentKeyStillCommitsLiteralAfterDrag() {
        var router = KeyboardInteractionRouter()
        let target = KeyboardInteractionTarget.key(
            "e",
            alternates: ["é", "è"],
            allowsSwipe: false
        )

        _ = router.handle(.press(target: target, at: .zero, time: 4))
        XCTAssertEqual(
            router.handle(.move(to: InteractionPoint(x: 40, y: 0), time: 4.1)),
            []
        )
        XCTAssertEqual(
            router.handle(.release(at: InteractionPoint(x: 40, y: 0), time: 4.2)),
            [.commitText("e"), .preview(nil), .pressed(nil)]
        )
    }

    func testCancellationMakesOutstandingDeadlinesHarmless() throws {
        var router = KeyboardInteractionRouter()
        let effects = router.handle(
            .press(target: .key("a", alternates: ["à"]), at: .zero, time: 5)
        )
        XCTAssertEqual(effects.feedbackEffects, [.feedback(.key)])
        let deadline = try XCTUnwrap(effects.compactMap(\.deadline).first)

        XCTAssertEqual(
            router.handle(.cancel),
            [.preview(nil), .pressed(nil)]
        )
        XCTAssertEqual(router.handle(.deadline(deadline)), [])
    }
}

private extension KeyboardInteractionEffect {
    var deadline: KeyboardInteractionDeadline? {
        guard case let .schedule(deadline) = self else { return nil }
        return deadline
    }
}

private extension Array where Element == KeyboardInteractionEffect {
    var feedbackEffects: [KeyboardInteractionEffect] {
        filter {
            guard case .feedback = $0 else { return false }
            return true
        }
    }
}
