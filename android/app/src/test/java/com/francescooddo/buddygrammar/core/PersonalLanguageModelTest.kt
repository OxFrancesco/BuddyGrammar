package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Test

class PersonalLanguageModelTest {

    @Test
    fun `predicts repeated continuations most frequent first`() {
        val model = PersonalLanguageModel()
        repeat(3) { model.learn("see", "tomorrow") }
        repeat(2) { model.learn("see", "you") }
        assertEquals(listOf("tomorrow", "you"), model.predictions("see", 2))
    }

    @Test
    fun `ignores single occurrence continuations`() {
        val model = PersonalLanguageModel()
        model.learn("see", "tomorrow")
        assertEquals(emptyList<String>(), model.predictions("see", 2))
    }

    @Test
    fun `completions require repeated use`() {
        val model = PersonalLanguageModel()
        repeat(3) { model.learn(null, "francesco") }
        model.learn(null, "fabulous")
        assertEquals(listOf("francesco"), model.completions("f", 2))
        assertEquals(listOf("francesco"), model.completions("fra", 2))
    }

    @Test
    fun `rejects non words`() {
        val model = PersonalLanguageModel()
        repeat(3) {
            model.learn(null, "12345")
            model.learn(null, "http://x.co")
        }
        assertEquals(emptyList<String>(), model.completions("1", 2))
        assertEquals(emptyList<String>(), model.completions("h", 2))
    }

    @Test
    fun `round trips through persistence`() {
        var persisted: String? = null
        val model = PersonalLanguageModel(onPersist = { persisted = it })
        repeat(3) { model.learn("ciao", "bella") }
        model.persist()

        val reloaded = PersonalLanguageModel(initialData = persisted)
        assertEquals(listOf("bella"), reloaded.predictions("ciao", 1))
        assertEquals(listOf("bella"), reloaded.completions("b", 1))
    }

    @Test
    fun `personal predictions outrank static bigrams in suggestions`() {
        val model = PersonalLanguageModel()
        repeat(2) { model.learn("good", "vibes") }
        val suggestions = SuggestionEngine.suggest("that sounds good ", model)
        assertEquals("vibes", suggestions.first().text)
    }
}
