package com.francescooddo.buddygrammar.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyboardLayoutPolicyTest {
    @Test
    fun `compact phones keep a continuous key grid`() {
        val spec = KeyboardLayoutPolicy.resolve(screenWidthDp = 411, screenHeightDp = 891)

        assertFalse(spec.usesSplitKeyGrid)
        assertEquals(0, spec.centerGapDp)
        assertEquals(6, spec.sidePaddingDp)
        assertEquals(48, spec.keyHeightDp)
    }

    @Test
    fun `unfolded and medium windows use a proportional split grid`() {
        val spec = KeyboardLayoutPolicy.resolve(screenWidthDp = 720, screenHeightDp = 850)

        assertTrue(spec.usesSplitKeyGrid)
        assertEquals(100, spec.centerGapDp)
        assertEquals(12, spec.sidePaddingDp)
        assertEquals(48, spec.keyHeightDp)
        assertEquals(64, spec.iconControlKeyWidthDp)
        assertEquals(96, spec.wideControlKeyWidthDp)
    }

    @Test
    fun `expanded tablets cap the center gap and increase side padding`() {
        val spec = KeyboardLayoutPolicy.resolve(screenWidthDp = 1280, screenHeightDp = 900)

        assertTrue(spec.usesSplitKeyGrid)
        assertEquals(140, spec.centerGapDp)
        assertEquals(20, spec.sidePaddingDp)
        assertEquals(20, spec.navigationBarSafetyGapDp)
    }

    @Test
    fun `short landscape windows compact every layer vertically`() {
        val spec = KeyboardLayoutPolicy.resolve(screenWidthDp = 800, screenHeightDp = 360)

        assertEquals(42, spec.keyHeightDp)
        assertEquals(150, spec.emojiPanelHeightDp)
        assertEquals(112, spec.handwritingCanvasHeightDp)
        assertEquals(168, spec.voicePanelHeightDp)
    }
}
