package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Test

class LanguageSupportTest {
    @Test
    fun `editor hint wins over the device language with an English fallback`() {
        assertEquals(
            "it-IT",
            LanguageSupport.preferredTag(listOf("it-IT"), listOf("en-US")),
        )
        assertEquals(
            "fr-FR",
            LanguageSupport.preferredTag(emptyList(), listOf("fr-FR")),
        )
        assertEquals(
            LanguageSupport.DEFAULT_LANGUAGE_TAG,
            LanguageSupport.preferredTag(listOf(" "), emptyList()),
        )
    }

    @Test
    fun `normalizes common detected three letter language codes`() {
        assertEquals("en", LanguageSupport.scope("eng"))
        assertEquals("it", LanguageSupport.scope("ita"))
        assertEquals("fr", LanguageSupport.scope("fra"))
    }
}
