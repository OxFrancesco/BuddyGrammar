package com.francescooddo.buddygrammar.core

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidIcuGraphemeBoundaryProviderTest {
    private val offsets = GraphemeClusterOffsets(AndroidIcuGraphemeBoundaryProvider)

    @Test
    fun androidIcuKeepsRepresentativeEmojiSequencesWhole() {
        assertEquals(
            11,
            offsets.utf16UnitsBeforeCursor("👨‍👩‍👧‍👦", 1, false),
        )
        assertEquals(4, offsets.utf16UnitsBeforeCursor("🇮🇹", 1, false))
        assertEquals(4, offsets.utf16UnitsBeforeCursor("👍🏽", 1, false))
        assertEquals(2, offsets.utf16UnitsBeforeCursor("e\u0301", 1, false))
    }
}
