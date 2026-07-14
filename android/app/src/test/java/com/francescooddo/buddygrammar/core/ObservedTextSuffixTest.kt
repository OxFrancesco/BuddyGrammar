package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ObservedTextSuffixTest {
    @Test
    fun `consumes an unchanged recognized final word once`() {
        val suffix = ObservedTextSuffix(maximumCharacters = 16)
        suffix.observe(committedText = "hello world", contextBeforeCursor = "Say hello world")

        assertTrue(suffix.consumeIfUnchanged("Say hello world"))
        assertFalse(suffix.consumeIfUnchanged("Say hello world"))
    }

    @Test
    fun `does not consume after an edit or when observed text ends at a boundary`() {
        val suffix = ObservedTextSuffix(maximumCharacters = 16)
        suffix.observe(committedText = "hello", contextBeforeCursor = "Say hello")
        suffix.retainIfUnchanged("Say hello!")
        assertFalse(suffix.consumeIfUnchanged("Say hello!"))

        suffix.observe(committedText = "hello.", contextBeforeCursor = "Say hello.")
        assertFalse(suffix.consumeIfUnchanged("Say hello."))
    }

    @Test
    fun `stores only the configured suffix bound`() {
        val suffix = ObservedTextSuffix(maximumCharacters = 5)
        suffix.observe(committedText = "hello", contextBeforeCursor = "A long prefix hello")

        assertTrue(suffix.consumeIfUnchanged("A different prefix hello"))
    }
}
