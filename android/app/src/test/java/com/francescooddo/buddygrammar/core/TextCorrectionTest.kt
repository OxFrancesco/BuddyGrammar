package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class TextCorrectionTest {
    private val extractor = TextContextExtractor(
        GraphemeBoundaryProvider { text ->
            buildList {
                add(0)
                Regex("\\X").findAll(text).forEach { match -> add(match.range.last + 1) }
            }.distinct().toIntArray()
        },
    )

    @Test
    fun `extracts sentence after previous terminator`() {
        val candidate = extractor.precedingSentence("First sentence. this need fixing ")
        assertEquals(" this need fixing ", candidate?.capturedText)
        assertEquals("this need fixing", candidate?.requestText)
        assertEquals(" This needs fixing. ", candidate?.replacement("This needs fixing."))
    }

    @Test
    fun `includes final punctuation and trailing whitespace`() {
        val candidate = extractor.precedingSentence("Previous! next sentence?  ")
        assertEquals(" next sentence?  ", candidate?.capturedText)
        assertEquals("next sentence?", candidate?.requestText)
    }

    @Test
    fun `treats newline as a boundary`() {
        val candidate = extractor.precedingSentence("Old line\nnew line")
        assertEquals("new line", candidate?.capturedText)
    }

    @Test
    fun `returns null for whitespace only context`() {
        assertNull(extractor.precedingSentence("   \n  "))
    }

    @Test
    fun `bounds long context`() {
        val candidate = extractor.precedingSentence("x".repeat(1_500), 1_000)
        assertEquals(1_000, candidate?.capturedText?.length)
    }

    @Test
    fun `extracts the full sentence around a cursor`() {
        val candidate = extractor.currentSentence(
            contextBeforeCursor = "Previous. this sentence ",
            contextAfterCursor = "need fixing. Next",
        )

        assertEquals(" this sentence need fixing.", candidate?.candidate?.capturedText)
        assertEquals(" this sentence ", candidate?.textBeforeCursor)
        assertEquals("need fixing.", candidate?.textAfterCursor)
        assertEquals("this sentence need fixing.", candidate?.candidate?.requestText)
    }

    @Test
    fun `uses the preceding sentence when the cursor follows punctuation`() {
        val candidate = extractor.currentSentence(
            contextBeforeCursor = "Previous. this need fixing.  ",
            contextAfterCursor = "Next sentence",
        )

        assertEquals(" this need fixing.  ", candidate?.candidate?.capturedText)
        assertEquals("", candidate?.textAfterCursor)
    }

    @Test
    fun `treats ellipsis as a current sentence boundary`() {
        val candidate = extractor.currentSentence(
            contextBeforeCursor = "Previous thought… this sentence ",
            contextAfterCursor = "need fixing… Next sentence",
        )

        assertEquals(" this sentence need fixing…", candidate?.candidate?.capturedText)
        assertEquals(" this sentence ", candidate?.textBeforeCursor)
        assertEquals("need fixing…", candidate?.textAfterCursor)
    }

    @Test
    fun `preceding sentence bound never starts inside an emoji ZWJ grapheme`() {
        val family = "👨‍👩‍👧‍👦"
        val candidate = extractor.precedingSentence(
            context = family + "abcde",
            maximumCharacters = 10,
        )

        assertEquals("abcde", candidate?.capturedText)
        assertEquals("abcde", candidate?.requestText)
    }

    @Test
    fun `current sentence bound never ends between a base and combining mark`() {
        val candidate = extractor.currentSentence(
            contextBeforeCursor = "",
            contextAfterCursor = "123456789e\u0301tail",
            maximumCharacters = 10,
        )

        assertEquals("123456789", candidate?.candidate?.capturedText)
        assertEquals("123456789", candidate?.textAfterCursor)
    }

    @Test
    fun `guard rejects explanations and oversized output`() {
        assertThrows(IllegalArgumentException::class.java) {
            CorrectionOutputGuard.sanitize("Here is the corrected text: Fine.", "bad")
        }
        assertThrows(IllegalArgumentException::class.java) {
            CorrectionOutputGuard.sanitize("x".repeat(501), "bad")
        }
        assertEquals("Fine.", CorrectionOutputGuard.sanitize("  Fine. \n", "bad"))
    }

    @Test
    fun `undo applies only while corrected text and anchors are unchanged`() {
        val undo = CorrectionUndoState(
            originalText = " this need fixing. ",
            replacementText = " This needs fixing. ",
            anchorBefore = "Previous.",
            anchorAfter = "Next",
        )

        assertEquals(
            true,
            undo.matches("Previous. This needs fixing. ", "Next"),
        )
        assertEquals(
            false,
            undo.matches("Previous. This needs fixing! ", "Next"),
        )
    }
}
