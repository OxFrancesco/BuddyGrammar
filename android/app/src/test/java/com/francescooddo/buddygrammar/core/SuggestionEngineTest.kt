package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SuggestionEngineTest {
    @Test
    fun `completes the word being typed by frequency`() {
        val suggestions = SuggestionEngine.suggest("I went th")

        assertTrue(suggestions.isNotEmpty())
        suggestions.filter { !it.isEmoji }.forEach { suggestion ->
            assertTrue(suggestion.text.startsWith("th"))
            assertEquals(2, suggestion.replaceBeforeCursor)
            assertTrue(suggestion.appendSpace)
        }
        assertEquals("the", suggestions.first().text)
    }

    @Test
    fun `matches the capitalization of the typed prefix`() {
        val suggestions = SuggestionEngine.suggest("Th")

        assertEquals("The", suggestions.first().text)
    }

    @Test
    fun `offers an emoji replacement while typing a mapped keyword`() {
        val suggestions = SuggestionEngine.suggest("that is fire")

        val emoji = suggestions.last()
        assertTrue(emoji.isEmoji)
        assertEquals("🔥", emoji.text)
        assertEquals("fire".length, emoji.replaceBeforeCursor)
    }

    @Test
    fun `offers an emoji replacement for the last completed word`() {
        val suggestions = SuggestionEngine.suggest("so much love ")

        val emoji = suggestions.last()
        assertTrue(emoji.isEmoji)
        assertEquals("❤️", emoji.text)
        assertEquals("love ".length, emoji.replaceBeforeCursor)
    }

    @Test
    fun `predicts the next word from the bigram table`() {
        val suggestions = SuggestionEngine.suggest("thank ")

        assertEquals("you", suggestions.first().text)
        assertEquals(0, suggestions.first().replaceBeforeCursor)
        assertTrue(suggestions.first().appendSpace)
    }

    @Test
    fun `predicts two bigram words when available`() {
        val words = SuggestionEngine.suggest("good ").filter { !it.isEmoji }.map { it.text }

        assertEquals(listOf("morning", "luck"), words)
    }

    @Test
    fun `falls back to common words after unknown words`() {
        val words = SuggestionEngine.suggest("zyzzyva ").filter { !it.isEmoji }.map { it.text }

        assertEquals(listOf("the", "I"), words)
    }

    @Test
    fun `capitalizes predictions at a sentence start`() {
        val words = SuggestionEngine.suggest("Done. ").filter { !it.isEmoji }.map { it.text }

        assertEquals(listOf("The", "I"), words)
        assertEquals(listOf("The", "I"), SuggestionEngine.suggest("").filter { !it.isEmoji }.map { it.text })
    }

    @Test
    fun `detects sentence starts`() {
        assertTrue(SuggestionEngine.isSentenceStart(""))
        assertTrue(SuggestionEngine.isSentenceStart("Hello. "))
        assertTrue(SuggestionEngine.isSentenceStart("Wait!"))
        assertTrue(SuggestionEngine.isSentenceStart("Line\n"))
        assertFalse(SuggestionEngine.isSentenceStart("Hello, "))
        assertFalse(SuggestionEngine.isSentenceStart("wor"))
    }

    @Test
    fun `never returns more than three suggestions`() {
        assertTrue(SuggestionEngine.suggest("th").size <= SuggestionEngine.MAX_SUGGESTIONS)
        assertTrue(SuggestionEngine.suggest("love ").size <= SuggestionEngine.MAX_SUGGESTIONS)
    }
}
