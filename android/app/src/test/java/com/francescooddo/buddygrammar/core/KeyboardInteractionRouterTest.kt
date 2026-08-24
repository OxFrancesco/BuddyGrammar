package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Test

class KeyboardInteractionRouterTest {
    @Test
    fun `letter and space haptics happen on press without a duplicate on release`() {
        val router = KeyboardInteractionRouter()
        val key = InteractionTarget.Key("a")

        assertEquals(
            InteractionEffect.Feedback(InteractionFeedback.KEY),
            router.handle(InteractionInput.Press(key, InteractionPoint.Zero, 0.0)).last(),
        )
        assertEquals(
            emptyList<InteractionEffect.Feedback>(),
            router.handle(InteractionInput.Release(InteractionPoint.Zero, 0.1))
                .filterIsInstance<InteractionEffect.Feedback>(),
        )

        assertEquals(
            InteractionEffect.Feedback(InteractionFeedback.KEY),
            router.handle(
                InteractionInput.Press(InteractionTarget.Space, InteractionPoint.Zero, 1.0),
            ).last(),
        )
        assertEquals(
            emptyList<InteractionEffect.Feedback>(),
            router.handle(InteractionInput.Release(InteractionPoint.Zero, 1.1))
                .filterIsInstance<InteractionEffect.Feedback>(),
        )
    }

    @Test
    fun `tap previews and commits its literal`() {
        val router = KeyboardInteractionRouter()
        val key = InteractionTarget.Key("e")

        assertEquals(
            listOf(
                InteractionEffect.Pressed(key),
                InteractionEffect.Preview("e"),
                InteractionEffect.Feedback(InteractionFeedback.KEY),
            ),
            router.handle(InteractionInput.Press(key, InteractionPoint.Zero, 0.0)),
        )
        assertEquals(
            listOf(
                InteractionEffect.CommitText("e"),
                InteractionEffect.Preview(null),
                InteractionEffect.Pressed(null),
            ),
            router.handle(InteractionInput.Release(InteractionPoint.Zero, 0.08)),
        )
    }

    @Test
    fun `long press chooses accent without committing base key`() {
        val router = KeyboardInteractionRouter()
        val press = router.handle(
            InteractionInput.Press(
                InteractionTarget.Key("e", listOf("é", "è", "ê")),
                InteractionPoint.Zero,
                1.0,
            ),
        )
        val deadline = press.deadline()

        assertEquals(
            listOf(
                InteractionEffect.ShowAlternates(listOf("é", "è", "ê"), 0),
                InteractionEffect.Feedback(InteractionFeedback.SELECTION),
            ),
            router.handle(InteractionInput.Deadline(deadline)),
        )
        assertEquals(
            listOf(InteractionEffect.ShowAlternates(listOf("é", "è", "ê"), 2)),
            router.handle(InteractionInput.Move(InteractionPoint(52.0, 0.0), 1.5)),
        )
        assertEquals(
            listOf(
                InteractionEffect.CommitText("ê"),
                InteractionEffect.HideAlternates,
                InteractionEffect.Preview(null),
                InteractionEffect.Pressed(null),
            ),
            router.handle(InteractionInput.Release(InteractionPoint(52.0, 0.0), 1.6)),
        )
    }

    @Test
    fun `spacebar drag moves cursor and suppresses space`() {
        val router = KeyboardInteractionRouter()
        router.handle(InteractionInput.Press(InteractionTarget.Space, InteractionPoint.Zero, 2.0))

        assertEquals(
            listOf(
                InteractionEffect.Preview(null),
                InteractionEffect.Feedback(InteractionFeedback.SELECTION),
                InteractionEffect.MoveCursor(2),
            ),
            router.handle(InteractionInput.Move(InteractionPoint(31.0, 2.0), 2.1)),
        )
        assertEquals(
            listOf(InteractionEffect.MoveCursor(1)),
            router.handle(InteractionInput.Move(InteractionPoint(47.0, 2.0), 2.15)),
        )
        assertEquals(
            listOf(InteractionEffect.Pressed(null)),
            router.handle(InteractionInput.Release(InteractionPoint(47.0, 2.0), 2.17)),
        )
    }

    @Test
    fun `stationary spacebar hold enters cursor mode and suppresses space`() {
        val router = KeyboardInteractionRouter()
        val press = router.handle(
            InteractionInput.Press(InteractionTarget.Space, InteractionPoint.Zero, 2.0),
        )
        val deadline = press.deadline()

        assertEquals(InteractionDeadline.Kind.CURSOR_ACTIVATION, deadline.kind)
        assertEquals(
            listOf(
                InteractionEffect.Preview(null),
                InteractionEffect.Feedback(InteractionFeedback.SELECTION),
            ),
            router.handle(InteractionInput.Deadline(deadline)),
        )
        assertEquals(
            listOf(InteractionEffect.Pressed(null)),
            router.handle(InteractionInput.Release(InteractionPoint.Zero, 2.2)),
        )
    }

    @Test
    fun `held delete remains character granular for every repeat`() {
        val router = KeyboardInteractionRouter()
        var effects = router.handle(
            InteractionInput.Press(InteractionTarget.Delete, InteractionPoint.Zero, 3.0),
        )
        assertEquals(
            listOf(
                InteractionEffect.Pressed(InteractionTarget.Delete),
                InteractionEffect.DeleteBackward,
                InteractionEffect.Feedback(InteractionFeedback.KEY),
            ),
            effects.take(3),
        )

        var deadline = effects.deadline()
        repeat(20) {
            effects = router.handle(InteractionInput.Deadline(deadline))
            assertEquals(InteractionEffect.DeleteBackward, effects.first())
            deadline = effects.deadline()
        }
    }

    @Test
    fun `swipe suppresses literal commit`() {
        val router = KeyboardInteractionRouter()
        val pressEffects = router.handle(
            InteractionInput.Press(InteractionTarget.Key("h"), InteractionPoint.Zero, 4.0),
        )
        assertEquals(
            listOf(InteractionEffect.Feedback(InteractionFeedback.KEY)),
            pressEffects.filterIsInstance<InteractionEffect.Feedback>(),
        )
        val move = InteractionPoint(30.0, 4.0)
        assertEquals(
            listOf(
                InteractionEffect.Preview(null),
                InteractionEffect.SwipeBegan(InteractionPoint.Zero),
                InteractionEffect.SwipeMoved(move),
            ),
            router.handle(InteractionInput.Move(move, 4.1)),
        )
        val release = InteractionPoint(55.0, 5.0)
        assertEquals(
            listOf(
                InteractionEffect.SwipeEnded(release),
                InteractionEffect.Pressed(null),
            ),
            router.handle(InteractionInput.Release(release, 4.2)),
        )
    }

    @Test
    fun `cancel keeps the single press feedback and suppresses commit`() {
        val router = KeyboardInteractionRouter()
        val pressEffects = router.handle(
            InteractionInput.Press(
                InteractionTarget.Key("a", listOf("à")),
                InteractionPoint.Zero,
                5.0,
            ),
        )
        val deadline = pressEffects.deadline()

        assertEquals(
            listOf(InteractionEffect.Feedback(InteractionFeedback.KEY)),
            pressEffects.filterIsInstance<InteractionEffect.Feedback>(),
        )
        assertEquals(
            listOf(InteractionEffect.Preview(null), InteractionEffect.Pressed(null)),
            router.handle(InteractionInput.Cancel),
        )
        assertEquals(
            emptyList<InteractionEffect>(),
            router.handle(InteractionInput.Deadline(deadline)),
        )
    }

    @Test
    fun `key with swipe disabled remains a literal even after a long drag`() {
        val router = KeyboardInteractionRouter()
        val key = InteractionTarget.Key("x", allowsSwipe = false)
        router.handle(InteractionInput.Press(key, InteractionPoint.Zero, 5.0))

        assertEquals(
            emptyList<InteractionEffect>(),
            router.handle(InteractionInput.Move(InteractionPoint(60.0, 0.0), 5.1)),
        )
        assertEquals(
            listOf(
                InteractionEffect.CommitText("x"),
                InteractionEffect.Preview(null),
                InteractionEffect.Pressed(null),
            ),
            router.handle(InteractionInput.Release(InteractionPoint(60.0, 0.0), 5.2)),
        )
    }

    private fun List<InteractionEffect>.deadline(): InteractionDeadline =
        filterIsInstance<InteractionEffect.Schedule>().first().deadline
}
