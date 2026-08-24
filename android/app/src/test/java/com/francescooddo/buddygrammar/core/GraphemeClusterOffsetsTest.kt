package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GraphemeClusterOffsetsTest {
    private val offsets = GraphemeClusterOffsets(
        GraphemeBoundaryProvider { text ->
            buildList {
                add(0)
                Regex("\\X").findAll(text).forEach { match -> add(match.range.last + 1) }
            }.distinct().toIntArray()
        },
    )

    @Test
    fun `backward offsets keep extended grapheme clusters whole`() {
        assertEquals(1, offsets.utf16UnitsBeforeCursor("abc", 1, false))
        assertEquals(2, offsets.utf16UnitsBeforeCursor("xe\u0301", 1, false))
        assertEquals(4, offsets.utf16UnitsBeforeCursor("x👍🏽", 1, false))
        assertEquals(4, offsets.utf16UnitsBeforeCursor("x🇮🇹", 1, false))
        assertEquals(
            11,
            offsets.utf16UnitsBeforeCursor("x👨‍👩‍👧‍👦", 1, false),
        )
    }

    @Test
    fun `forward offsets keep extended grapheme clusters whole`() {
        assertEquals(1, offsets.utf16UnitsAfterCursor("abc", 1, false))
        assertEquals(2, offsets.utf16UnitsAfterCursor("e\u0301x", 1, false))
        assertEquals(4, offsets.utf16UnitsAfterCursor("👍🏽x", 1, false))
        assertEquals(4, offsets.utf16UnitsAfterCursor("🇮🇹x", 1, false))
        assertEquals(
            11,
            offsets.utf16UnitsAfterCursor("👨‍👩‍👧‍👦x", 1, false),
        )
    }

    @Test
    fun `multiple steps and document boundaries resolve to utf16 offsets`() {
        assertEquals(5, offsets.utf16UnitsBeforeCursor("a🇮🇹b", 2, false))
        assertEquals(5, offsets.utf16UnitsAfterCursor("🇮🇹ab", 2, false))
        assertEquals(3, offsets.utf16UnitsBeforeCursor("abc", 20, false))
        assertEquals(3, offsets.utf16UnitsAfterCursor("abc", 20, false))
        assertEquals(0, offsets.utf16UnitsBeforeCursor("", 1, false))
        assertEquals(0, offsets.utf16UnitsAfterCursor("", 1, false))
    }

    @Test
    fun `a boundary touching a truncated context edge is rejected conservatively`() {
        assertNull(offsets.utf16UnitsBeforeCursor("🇮🇹", 1, true))
        assertNull(offsets.utf16UnitsAfterCursor("🇮🇹", 1, true))

        assertEquals(1, offsets.utf16UnitsBeforeCursor("abcdef", 1, true))
        assertEquals(1, offsets.utf16UnitsAfterCursor("abcdef", 1, true))
    }
}
