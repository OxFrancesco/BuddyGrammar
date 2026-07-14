package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LocalWordCorrectorTest {
    @Test
    fun `corrects transposed letters and adjacent key substitutions`() {
        assertEquals("the", LocalWordCorrector.bestCorrection("teh", listOf("the", "ten")))
        assertEquals("Word", LocalWordCorrector.bestCorrection("Wprd", listOf("word", "work")))
        assertEquals("WORD", LocalWordCorrector.bestCorrection("WPRD", listOf("word", "work")))
    }

    @Test
    fun `does not alter known or distant words`() {
        assertNull(LocalWordCorrector.bestCorrection("cat", listOf("cat", "car")))
        assertNull(LocalWordCorrector.bestCorrection("zzzz", listOf("word", "work")))
        assertNull(LocalWordCorrector.bestCorrection("a", listOf("an", "at")))
        assertNull(LocalWordCorrector.bestCorrection("hel", listOf("help")))
    }
}
