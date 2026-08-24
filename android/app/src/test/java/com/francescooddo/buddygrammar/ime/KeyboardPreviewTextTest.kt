package com.francescooddo.buddygrammar.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class KeyboardPreviewTextTest {
    @Test
    fun `bounded preview truncates by grapheme without splitting emoji`() {
        val family = "👨‍👩‍👧‍👦"
        val prefix = "x".repeat(24) + family
        val suffix = family + "y".repeat(24)

        val preview = boundedChangeText(prefix, "😀", suffix)

        assertEquals("…${"x".repeat(23)}$family⟦😀⟧$family${"y".repeat(23)}…", preview)
        assertFalse(preview.hasUnpairedSurrogate())
    }

    private fun String.hasUnpairedSurrogate(): Boolean {
        var index = 0
        while (index < length) {
            when {
                this[index].isHighSurrogate() -> {
                    if (index + 1 >= length || !this[index + 1].isLowSurrogate()) return true
                    index += 2
                }
                this[index].isLowSurrogate() -> return true
                else -> index += 1
            }
        }
        return false
    }
}
