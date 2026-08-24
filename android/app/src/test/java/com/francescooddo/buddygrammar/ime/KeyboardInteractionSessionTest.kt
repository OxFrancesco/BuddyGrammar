package com.francescooddo.buddygrammar.ime

import com.francescooddo.buddygrammar.core.InteractionCommand
import com.francescooddo.buddygrammar.core.InteractionDeadline
import com.francescooddo.buddygrammar.core.InteractionPoint
import com.francescooddo.buddygrammar.core.InteractionTarget
import com.francescooddo.buddygrammar.core.KeyboardInteractionSession
import com.francescooddo.buddygrammar.core.KeyboardPointerBinding
import com.francescooddo.buddygrammar.core.KeySpaceTransform
import com.francescooddo.buddygrammar.core.SwipePoint
import com.francescooddo.buddygrammar.core.SwipePathSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyboardInteractionSessionTest {
    @Test
    fun `letter pointer session maps local geometry to adaptive and swipe commands`() {
        val target = InteractionTarget.Key("e", allowsSwipe = true)
        val binding = KeyboardPointerBinding.Letter(
            target = target,
            transform = KeySpaceTransform(
                centerX = 2.5,
                centerY = 0.5,
                width = 100.0,
                height = 50.0,
            ),
            swipeTransform = KeySpaceTransform(
                centerX = 2.0,
                centerY = 0.0,
                width = 100.0,
                height = 50.0,
            ),
        )
        val session = KeyboardInteractionSession()

        val press = session.press(binding, InteractionPoint(25.0, 25.0), 1.0)
        assertEquals(target, press.visualState.pressedTarget)
        assertEquals("e", press.visualState.previewText)

        val release = session.release(InteractionPoint(25.0, 25.0), 1.1)
        assertEquals(
            InteractionCommand.CommitAdaptiveKey("e", SwipePoint(2.25, 0.5)),
            release.commands.first(),
        )
        assertNull(release.visualState.pressedTarget)

        session.press(binding, InteractionPoint(50.0, 25.0), 2.0)
        session.move(InteractionPoint(80.0, 25.0), 2.1)
        session.move(InteractionPoint(80.0, 25.0), 2.15)
        val swipeRelease = session.release(InteractionPoint(100.0, 25.0), 2.2)
        assertEquals(
            listOf(
                SwipePathSample(2.0, 0.0, 2_000.0),
                SwipePathSample(2.3, 0.0, 2_100.0),
                SwipePathSample(2.3, 0.0, 2_150.0),
                SwipePathSample(2.5, 0.0, 2_200.0),
            ),
            swipeRelease.commands.filterIsInstance<InteractionCommand.CommitSwipe>()
                .single()
                .samples,
        )
    }

    @Test
    fun `accent deadline commits the selected literal alternate`() {
        val target = InteractionTarget.Key("e", listOf("é", "è", "ê"), allowsSwipe = false)
        val session = KeyboardInteractionSession()
        val press = session.press(
            KeyboardPointerBinding.Letter(
                target,
                KeySpaceTransform(2.5, 0.5, 100.0, 50.0),
            ),
            InteractionPoint.Zero,
            3.0,
        )
        val deadline = press.commands.filterIsInstance<InteractionCommand.Schedule>().single().deadline

        val alternate = session.deadline(deadline)
        assertEquals(listOf("é", "è", "ê"), alternate.visualState.alternates)
        session.move(InteractionPoint(52.0, 0.0), 3.5)
        val release = session.release(InteractionPoint(52.0, 0.0), 3.6)

        assertEquals(
            listOf(InteractionCommand.CommitLiteralText("ê")),
            release.commands.filterIsInstance<InteractionCommand.CommitLiteralText>(),
        )
        assertNull(release.visualState.previewText)
    }

    @Test
    fun `space binding degrades to a space when cursor movement is unavailable`() {
        val session = KeyboardInteractionSession()
        val disabledPress = session.press(
            KeyboardPointerBinding.Space(cursorMovementEnabled = false),
            InteractionPoint.Zero,
            4.0,
        )
        val disabledDeadline = disabledPress.commands
            .filterIsInstance<InteractionCommand.Schedule>()
            .single()
            .deadline

        assertEquals(emptyList<InteractionCommand>(), session.move(InteractionPoint(50.0, 0.0), 4.1).commands)
        assertEquals(emptyList<InteractionCommand>(), session.deadline(disabledDeadline).commands)
        assertEquals(
            listOf(InteractionCommand.CommitSpace),
            session.release(InteractionPoint(50.0, 0.0), 4.2).commands
                .filterIsInstance<InteractionCommand.CommitSpace>(),
        )

        session.press(
            KeyboardPointerBinding.Space(cursorMovementEnabled = true),
            InteractionPoint.Zero,
            5.0,
        )
        assertEquals(
            listOf(InteractionCommand.MoveCursor(2)),
            session.move(InteractionPoint(31.0, 0.0), 5.2).commands
                .filterIsInstance<InteractionCommand.MoveCursor>(),
        )
    }

    @Test
    fun `delete binding exposes only character repeat commands`() {
        val session = KeyboardInteractionSession()
        var update = session.press(
            KeyboardPointerBinding.Delete,
            InteractionPoint.Zero,
            6.0,
        )
        assertEquals(InteractionCommand.DeleteBackward, update.commands.first())
        var deadline: InteractionDeadline = update.commands
            .filterIsInstance<InteractionCommand.Schedule>()
            .single()
            .deadline

        repeat(20) {
            update = session.deadline(deadline)
            assertEquals(InteractionCommand.DeleteBackward, update.commands.first())
            deadline = update.commands.filterIsInstance<InteractionCommand.Schedule>().single().deadline
        }
    }

    @Test
    fun `timed swipe capture is bounded while retaining down end and dwell samples`() {
        val target = InteractionTarget.Key("e")
        val binding = KeyboardPointerBinding.Letter(
            target = target,
            transform = KeySpaceTransform(2.5, 0.5, 100.0, 50.0),
            swipeTransform = KeySpaceTransform(2.0, 0.0, 100.0, 50.0),
        )
        val session = KeyboardInteractionSession()
        session.press(binding, InteractionPoint(50.0, 25.0), 10.0)
        session.move(InteractionPoint(80.0, 25.0), 10.01)
        repeat(1_000) { index ->
            session.move(InteractionPoint(80.0, 25.0), 10.02 + index * 0.01)
        }
        val command = session.release(InteractionPoint(100.0, 25.0), 20.1)
            .commands
            .filterIsInstance<InteractionCommand.CommitSwipe>()
            .single()

        assertTrue(command.samples.size <= 256)
        assertEquals(SwipePathSample(2.0, 0.0, 10_000.0), command.samples.first())
        assertEquals(SwipePathSample(2.5, 0.0, 20_100.0), command.samples.last())
        assertTrue(command.samples.count { it.x == 2.3 && it.y == 0.0 } >= 3)
    }
}
