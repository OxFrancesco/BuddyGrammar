package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Test

class WordTokenNormalizerTest {
    @Test
    fun `raw trailing word preserves apostrophe and normalization style`() {
        assertEquals("l'ho", WordTokenNormalizer.rawTrailingWord("say l'ho"))
        assertEquals("l’ho", WordTokenNormalizer.rawTrailingWord("say l’ho"))

        val decomposed = "cafe\u0301"
        assertEquals(decomposed, WordTokenNormalizer.rawTrailingWord("say $decomposed"))
        assertEquals("l’ho", WordTokenNormalizer.canonicalize("l'ho"))
    }
}
