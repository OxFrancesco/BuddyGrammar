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

    @Test
    fun `two word context outranks a more frequent one word continuation`() {
        val model = PersonalLanguageModel()
        repeat(2) { model.learnCommittedText("I like coffee") }
        repeat(4) { model.learnCommittedText("They like tea") }

        assertEquals(listOf("coffee", "tea"), model.predictions(listOf("I", "like"), 2))
        assertEquals(listOf("tea", "coffee"), model.predictions(listOf("They", "like"), 2))
    }

    @Test
    fun `trigram context round trips while legacy unigram and bigram data still decodes`() {
        var persisted: String? = null
        val model = PersonalLanguageModel(
            initialData = "u legacy 3\nb see you 2\n",
            onPersist = { persisted = it },
        )
        repeat(2) { model.learnCommittedText("we ship tomorrow") }
        repeat(4) { model.learnCommittedText("they ship today") }
        model.persist()

        val reloaded = PersonalLanguageModel(initialData = persisted)
        assertEquals(listOf("legacy"), reloaded.completions("leg", 1))
        assertEquals(listOf("you"), reloaded.predictions("see", 1))
        assertEquals(listOf("tomorrow", "today"), reloaded.predictions(listOf("we", "ship"), 2))
    }

    @Test
    fun `committed text learns within sentences without crossing boundaries`() {
        val model = PersonalLanguageModel()
        repeat(2) { model.learnCommittedText("See you tomorrow. Fresh start now\nNew line") }

        assertEquals(listOf("tomorrow"), model.predictions(listOf("see", "you"), 1))
        assertEquals(emptyList<String>(), model.predictions(listOf("you", "tomorrow"), 1))
        assertEquals(listOf("start"), model.predictions("fresh", 1))
        assertEquals(emptyList<String>(), model.predictions("now", 1))
        assertEquals(listOf("line"), model.predictions("new", 1))
    }

    @Test
    fun `recognized multiword text continues the cursor context`() {
        val model = PersonalLanguageModel()
        repeat(2) { model.learnCommittedText("tomorrow morning", "I will see you ") }

        assertEquals(listOf("tomorrow"), model.predictions(listOf("see", "you"), 1))
        assertEquals(listOf("morning"), model.predictions(listOf("you", "tomorrow"), 1))
    }

    @Test
    fun `personal vocabulary and predictions are isolated by language`() {
        val model = PersonalLanguageModel()
        repeat(3) {
            model.learnCommittedText("I like coffee", languageTag = "en-US")
            model.learnCommittedText("mi piace caffè", languageTag = "it-IT")
        }

        assertEquals(listOf("coffee"), model.predictions(listOf("I", "like"), 1, "en-GB"))
        assertEquals(emptyList<String>(), model.predictions(listOf("I", "like"), 1, "it-IT"))
        assertEquals(listOf("caffè"), model.predictions(listOf("mi", "piace"), 1, "it"))
        assertEquals(listOf("caffè"), model.completions("caf", 1, "it-CH"))
        assertEquals(emptyList<String>(), model.completions("caf", 1, "en-US"))
    }

    @Test
    fun `non English language records round trip alongside legacy English data`() {
        var persisted: String? = null
        val model = PersonalLanguageModel(
            initialData = "u legacy 3\nb see you 2\nt we ship today 2\n",
            onPersist = { persisted = it },
        )
        repeat(3) { model.learnCommittedText("mi piace caffè", languageTag = "it-IT") }
        model.persist()

        val reloaded = PersonalLanguageModel(initialData = persisted)
        assertEquals(listOf("legacy"), reloaded.completions("leg", 1, "en-US"))
        assertEquals(listOf("you"), reloaded.predictions("see", 1, "en-US"))
        assertEquals(listOf("today"), reloaded.predictions(listOf("we", "ship"), 1, "en-US"))
        assertEquals(listOf("caffè"), reloaded.predictions(listOf("mi", "piace"), 1, "it-IT"))
        assertEquals(emptyList<String>(), reloaded.predictions(listOf("mi", "piace"), 1, "en-US"))
    }
}
