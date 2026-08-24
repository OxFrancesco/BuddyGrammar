package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AutomaticSuggestionReplacementTest {
    @Test
    fun `requires exact captured context and explicit boundary`() {
        val replacement = AutomaticSuggestionReplacement.create(
            originalText = "teh",
            replacementText = "the",
            boundaryText = " ",
            precedingContext = "Please type ",
            source = AutomaticSuggestionSource.SPELLING,
        )

        assertNotNull(replacement)
        requireNotNull(replacement)
        assertEquals("the ", replacement.insertion)
        assertTrue(replacement.matches("Please type teh", 3, "the "))
        assertFalse(replacement.matches("Unrelated teh", 3, "the "))
        assertFalse(replacement.matches("Please type teh", 2, "the "))
        assertFalse(replacement.matches("Please type teh", 3, "the"))
    }

    @Test
    fun `rejects empty and no-op metadata`() {
        assertNull(
            AutomaticSuggestionReplacement.create(
                originalText = "",
                replacementText = "the",
                boundaryText = " ",
                precedingContext = "",
                source = AutomaticSuggestionSource.SPELLING,
            ),
        )
        assertNull(
            AutomaticSuggestionReplacement.create(
                originalText = "the",
                replacementText = "the",
                boundaryText = "",
                precedingContext = "",
                source = AutomaticSuggestionSource.SWIPE,
            ),
        )
    }

    @Test
    fun `render ownership binds a replacement to one field and language`() {
        val replacement = requireNotNull(
            AutomaticSuggestionReplacement.create(
                originalText = "teh",
                replacementText = "the",
                boundaryText = " ",
                precedingContext = "Type ",
                source = AutomaticSuggestionSource.SPELLING,
            ),
        ).ownedBy(
            fieldEpoch = 12,
            fieldIdentifier = "field-a",
            languageTag = "en-US",
        )

        assertTrue(
            replacement.isOwnedBy(
                fieldEpoch = 12,
                fieldIdentifier = "field-a",
                languageTag = "en-US",
            ),
        )
        assertFalse(
            replacement.isOwnedBy(
                fieldEpoch = 13,
                fieldIdentifier = "field-a",
                languageTag = "en-US",
            ),
        )
        assertFalse(
            replacement.isOwnedBy(
                fieldEpoch = 12,
                fieldIdentifier = "field-b",
                languageTag = "en-US",
            ),
        )
        assertFalse(
            replacement.isOwnedBy(
                fieldEpoch = 12,
                fieldIdentifier = "field-a",
                languageTag = "it-IT",
            ),
        )
    }
}
