package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class RankedLanguageLexiconTest {
    @Test
    fun `bundled contract language packs have expected isolated ranks`() {
        val lexicon = contractLexicon()

        assertEquals(8_000, lexicon.wordCount("en-US"))
        assertEquals(1_096, lexicon.wordCount("it-IT"))
        assertNotNull(lexicon.rank("home", "en"))
        assertNull(lexicon.rank("home", "it"))
        assertNotNull(lexicon.rank("dare", "it"))
        assertNull(lexicon.rank("dare", "en"))
    }

    @Test
    fun `Italian lookup preserves canonical accents and apostrophes`() {
        val lexicon = contractLexicon()

        assertEquals("perché", lexicon.match("perche", "it")?.display)
        assertEquals("l’ho", lexicon.match("l'ho", "it-IT")?.display)
        assertEquals(listOf("c’è"), lexicon.completions("c'", "it-CH", 1))
    }
}

internal fun contractLexicon(): RankedLanguageLexicon = RankedLanguageLexicon.parse(
    mapOf(
        "en" to contractLexiconSource("en"),
        "it" to contractLexiconSource("it"),
    ),
)

private fun contractLexiconSource(languageId: String): String {
    val path = "keyboard-contract/lexicons/$languageId-core.txt"
    return requireNotNull(RankedLanguageLexiconTest::class.java.classLoader?.getResourceAsStream(path)) {
        "Missing contract lexicon $path"
    }.bufferedReader(Charsets.UTF_8).use { it.readText() }
}
