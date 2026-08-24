package com.francescooddo.buddygrammar.ime

import com.francescooddo.buddygrammar.core.InteractionCommand
import com.francescooddo.buddygrammar.core.InteractionPoint
import com.francescooddo.buddygrammar.core.InteractionTarget
import com.francescooddo.buddygrammar.core.KeyboardPointerBinding
import com.francescooddo.buddygrammar.core.KeySpaceTransform
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class KeyboardPointerSessionAdapterTest {
    private val bindingA = KeyboardPointerBinding.Letter(
        target = InteractionTarget.Key("a"),
        transform = KeySpaceTransform(0.0, 0.0, 40.0, 40.0),
    )
    private val bindingB = KeyboardPointerBinding.Letter(
        target = InteractionTarget.Key("b"),
        transform = KeySpaceTransform(1.0, 0.0, 40.0, 40.0),
    )

    @Test
    fun `non-owner move release and cancel cannot mutate the active key session`() {
        val adapter = KeyboardPointerSessionAdapter<Long>()

        val firstDown = adapter.press(1L, bindingA, InteractionPoint.Zero, 1.0)
        assertEquals(bindingA.target, firstDown?.visualState?.pressedTarget)

        assertNull(adapter.press(2L, bindingB, InteractionPoint.Zero, 1.01))
        assertNull(adapter.move(2L, InteractionPoint(90.0, 0.0), 1.02))
        assertNull(adapter.release(2L, InteractionPoint.Zero, 1.03))
        assertNull(adapter.cancel(2L))
        assertEquals(bindingA.target, adapter.visualState.pressedTarget)

        val firstUp = requireNotNull(adapter.release(1L, InteractionPoint.Zero, 1.1))
        assertEquals(
            listOf(InteractionCommand.CommitAdaptiveKey("a", bindingA.transform.map(InteractionPoint.Zero))),
            firstUp.commands.filterIsInstance<InteractionCommand.CommitAdaptiveKey>(),
        )

        val secondDown = adapter.press(2L, bindingB, InteractionPoint.Zero, 1.2)
        assertEquals(bindingB.target, secondDown?.visualState?.pressedTarget)
    }

    @Test
    fun `only owner cancel clears the session`() {
        val adapter = KeyboardPointerSessionAdapter<Long>()
        assertNotNull(adapter.press(7L, bindingA, InteractionPoint.Zero, 2.0))

        assertNull(adapter.cancel(8L))
        assertEquals(bindingA.target, adapter.visualState.pressedTarget)

        val cancelled = requireNotNull(adapter.cancel(7L))
        assertNull(cancelled.visualState.pressedTarget)
    }
}
