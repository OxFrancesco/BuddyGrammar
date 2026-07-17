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
    fun `explicit rejection removes unigram bigram and trigram evidence`() {
        val model = PersonalLanguageModel()
        repeat(3) { model.learn(listOf("type", "this"), "teh") }

        model.reject(listOf("type", "this"), "teh")

        assertEquals(2, model.usageCount("teh"))
        assertEquals(listOf("teh"), model.predictions("this", 1))
        assertEquals(listOf("teh"), model.predictions(listOf("type", "this"), 1))
        assertEquals(emptyList<String>(), model.completions("t", 1))

        model.reject(listOf("type", "this"), "teh")

        assertEquals(1, model.usageCount("teh"))
        assertEquals(emptyList<String>(), model.predictions("this", 1))
        assertEquals(emptyList<String>(), model.predictions(listOf("type", "this"), 1))
    }

    @Test
    fun `previous word rejection uses the same explicit feedback path`() {
        val model = PersonalLanguageModel()
        repeat(3) { model.learn("type", "teh") }

        model.reject("type", "teh")

        assertEquals(2, model.usageCount("teh"))
        assertEquals(listOf("teh"), model.predictions("type", 1))
        assertEquals(emptyList<String>(), model.completions("t", 1))
    }

    @Test
    fun `old aggregate counts decay every thirty elapsed days`() {
        var now = 1_000L
        val model = PersonalLanguageModel(nowMillis = { now })
        repeat(8) { model.learn(listOf("keep", "typing"), "temporary") }
        assertEquals(8, model.usageCount("temporary"))

        now += 61 * DAY_MILLIS

        assertEquals(2, model.usageCount("temporary"))
        assertEquals(listOf("temporary"), model.predictions("typing", 1))
        assertEquals(listOf("temporary"), model.predictions(listOf("keep", "typing"), 1))
    }

    @Test
    fun `decay timestamp round trips while legacy snapshots start from load time`() {
        var now = 1_000L
        var persisted: String? = null
        val model = PersonalLanguageModel(
            onPersist = { persisted = it },
            nowMillis = { now },
        )
        repeat(8) { model.learn(null, "temporary") }
        model.persist()

        now += 31 * DAY_MILLIS
        val reloaded = PersonalLanguageModel(initialData = persisted, nowMillis = { now })
        assertEquals(4, reloaded.usageCount("temporary"))

        var legacyNow = 365 * DAY_MILLIS
        val legacy = PersonalLanguageModel(
            initialData = "u legacy 8\nb see you 2\nt we ship today 2\n",
            nowMillis = { legacyNow },
        )
        assertEquals(8, legacy.usageCount("legacy"))
        assertEquals(listOf("you"), legacy.predictions("see", 1))
        assertEquals(listOf("today"), legacy.predictions(listOf("we", "ship"), 1))

        legacyNow += 31 * DAY_MILLIS
        assertEquals(4, legacy.usageCount("legacy"))
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
        val model = PersonalLanguageModel(null) { persisted = it }
        repeat(3) { model.learn("ciao", "bella") }
        model.persist()

        val reloaded = PersonalLanguageModel(initialData = persisted)
        assertEquals(listOf("bella"), reloaded.predictions("ciao", 1))
        assertEquals(listOf("bella"), reloaded.completions("b", 1))
    }

    @Test
    fun `reset clears live counts and persists an empty snapshot immediately`() {
        var persisted: String? = null
        val model = PersonalLanguageModel(onPersist = { persisted = it })
        repeat(3) { model.learn("keep", "privateword") }
        model.persist()
        assertEquals(3, model.usageCount("privateword"))

        model.reset()

        assertEquals(0, model.usageCount("privateword"))
        assertEquals("", persisted)
        assertEquals(0, PersonalLanguageModel(initialData = persisted).usageCount("privateword"))
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

    private companion object {
        const val DAY_MILLIS = 24L * 60L * 60L * 1_000L
    }
}
