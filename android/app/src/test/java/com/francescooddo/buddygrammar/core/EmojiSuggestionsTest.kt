package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EmojiSuggestionsTest {
    @Test
    fun `maps known keywords to emoji`() {
        assertEquals("🔥", EmojiSuggestions.emojiFor("fire"))
        assertEquals("💯", EmojiSuggestions.emojiFor("100"))
        assertEquals("❤️", EmojiSuggestions.emojiFor("love"))
        assertEquals("❤️", EmojiSuggestions.emojiFor("heart"))
        assertEquals("🙏", EmojiSuggestions.emojiFor("thanks"))
        assertEquals("🔜", EmojiSuggestions.emojiFor("soon"))
    }

    @Test
    fun `matching is case-insensitive and trims whitespace`() {
        assertEquals("😂", EmojiSuggestions.emojiFor("LOL"))
        assertEquals("👌", EmojiSuggestions.emojiFor(" Okay "))
    }

    @Test
    fun `unknown words have no emoji`() {
        assertNull(EmojiSuggestions.emojiFor("keyboard"))
        assertNull(EmojiSuggestions.emojiFor(""))
    }
}
