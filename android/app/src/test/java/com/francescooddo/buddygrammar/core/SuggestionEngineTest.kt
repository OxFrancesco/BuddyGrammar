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

    @Test
    fun `uses two word personal context for next word predictions`() {
        val model = PersonalLanguageModel()
        repeat(2) { model.learnCommittedText("I like coffee") }
        repeat(4) { model.learnCommittedText("They like tea") }

        assertEquals("coffee", SuggestionEngine.suggest("I like ", model).first().text)
        assertEquals("tea", SuggestionEngine.suggest("They like ", model).first().text)
    }

    @Test
    fun `puts an obvious typo correction before prefix completions`() {
        val suggestion = SuggestionEngine.suggest("teh").first()

        assertEquals("the", suggestion.text)
        assertEquals(SuggestionKind.CORRECTION, suggestion.kind)
        assertEquals(3, suggestion.replaceBeforeCursor)
        assertTrue(suggestion.appendSpace)
        assertFalse(suggestion.isEmoji)
        assertEquals(
            AutomaticSuggestionSource.SPELLING,
            suggestion.automaticReplacement?.source,
        )
        assertEquals("teh", suggestion.automaticReplacement?.originalText)
    }

    @Test
    fun `correction metadata preserves the exact rendered apostrophe and context`() {
        val lexicon = RankedLanguageLexicon(
            mapOf("it" to listOf("l’ho")),
        )

        val suggestion = SuggestionEngine.suggest(
            textBeforeCursor = "Dico l'ha",
            languageTag = "it-IT",
            lexicon = lexicon,
        ).first { it.kind == SuggestionKind.CORRECTION }

        assertEquals("l’ho", suggestion.text)
        assertEquals(4, suggestion.replaceBeforeCursor)
        assertEquals("l'ha", suggestion.automaticReplacement?.originalText)
        assertEquals("Dico ", suggestion.automaticReplacement?.precedingContext)
        assertEquals(" ", suggestion.automaticReplacement?.boundaryText)
        assertEquals(
            AutomaticSuggestionSource.SPELLING,
            suggestion.automaticReplacement?.source,
        )
    }

    @Test
    fun `correction metadata preserves decomposed editor text for exact rollback`() {
        val rawTypedWord = "cafe\u0300"
        val lexicon = RankedLanguageLexicon(
            mapOf("it" to listOf("café")),
        )

        val suggestion = SuggestionEngine.suggest(
            textBeforeCursor = "Un $rawTypedWord",
            languageTag = "it-IT",
            lexicon = lexicon,
        ).first { it.kind == SuggestionKind.CORRECTION }

        assertEquals("café", suggestion.text)
        assertEquals(rawTypedWord.length, suggestion.replaceBeforeCursor)
        assertEquals(rawTypedWord, suggestion.automaticReplacement?.originalText)
        assertEquals("Un ", suggestion.automaticReplacement?.precedingContext)
    }

    @Test
    fun `only true corrections carry automatic replacement metadata`() {
        val ordinarySuggestions = buildList {
            addAll(SuggestionEngine.suggest("hel"))
            addAll(SuggestionEngine.suggest("thank "))
            addAll(SuggestionEngine.suggest("fire"))
        }

        assertTrue(
            ordinarySuggestions
                .filter { it.kind != SuggestionKind.CORRECTION }
                .all { it.automaticReplacement == null },
        )
    }

    @Test
    fun `never suggest suppresses only the chosen correction pair`() {
        val model = PersonalLanguageModel()
        assertTrue(model.suppressCorrection("teh", "the", "en-US"))

        assertTrue(
            SuggestionEngine.suggest("teh", model, "en-GB")
                .none { it.kind == SuggestionKind.CORRECTION },
        )
        assertEquals(
            "the",
            SuggestionEngine.suggest("teh", PersonalLanguageModel(), "en-US").first().text,
        )
    }

    @Test
    fun `add to dictionary immediately protects accepted spelling`() {
        val model = PersonalLanguageModel()
        assertTrue(model.addToDictionary("teh", "en-US"))

        assertTrue(
            SuggestionEngine.suggest("teh", model, "en-US")
                .none { it.kind == SuggestionKind.CORRECTION },
        )
    }

    @Test
    fun `restored spelling needs repeated evidence before correction is protected`() {
        val model = PersonalLanguageModel()
        model.learnCommittedText("teh", languageTag = "en-US")

        assertEquals(
            "the",
            SuggestionEngine.suggest("teh", model, "en-US").first().text,
        )

        repeat(2) { model.learnCommittedText("teh", languageTag = "en-US") }
        assertTrue(
            SuggestionEngine.suggest("teh", model, "en-US")
                .none { it.kind == SuggestionKind.CORRECTION },
        )
    }

    @Test
    fun `classifies a word extending the prefix as a completion`() {
        val suggestions = SuggestionEngine.suggest("hel")

        assertTrue(suggestions.isNotEmpty())
        assertTrue(suggestions.none { it.kind == SuggestionKind.CORRECTION })
        assertTrue(suggestions.all { it.kind == SuggestionKind.COMPLETION })
    }

    @Test
    fun `suppresses English priors and local corrections outside English`() {
        assertTrue(SuggestionEngine.suggest("hel", languageTag = "it-IT").isEmpty())
        assertTrue(SuggestionEngine.suggest("teh", languageTag = "it-IT").isEmpty())
        assertTrue(SuggestionEngine.suggest("unknown ", languageTag = "it-IT").isEmpty())
        assertTrue(SuggestionEngine.suggest("hel").isNotEmpty())
    }

    @Test
    fun `still offers language scoped personal predictions outside English`() {
        val model = PersonalLanguageModel()
        repeat(2) {
            model.learnCommittedText("mi piace caffè", languageTag = "it-IT")
            model.learnCommittedText("mi piace tea", languageTag = "en-US")
        }

        val italian = SuggestionEngine.suggest("mi piace ", model, languageTag = "it-IT")
        assertEquals(listOf("caffè"), italian.map { it.text })
        assertTrue(italian.all { it.kind == SuggestionKind.PREDICTION })
    }

    @Test
    fun `editor policy can disable every suggestion including emoji`() {
        assertTrue(
            SuggestionEngine.suggest("hel", suggestionsAllowed = false).isEmpty(),
        )
        assertTrue(
            SuggestionEngine.suggest("love", suggestionsAllowed = false).isEmpty(),
        )
    }

    @Test
    fun `shared language packs provide ranked completions without leakage`() {
        val lexicon = contractLexicon()

        assertEquals(
            "home",
            SuggestionEngine.suggest("I went hom", languageTag = "en-US", lexicon = lexicon)
                .first().text,
        )
        assertEquals(
            "dare",
            SuggestionEngine.suggest("voglio dar", languageTag = "it-IT", lexicon = lexicon)
                .first().text,
        )
        assertTrue(
            SuggestionEngine.suggest("voglio hom", languageTag = "it-IT", lexicon = lexicon)
                .none { it.text.equals("home", ignoreCase = true) },
        )
    }

    @Test
    fun `Italian completions canonicalize accents and apostrophes`() {
        val lexicon = contractLexicon()

        assertEquals(
            "perché",
            SuggestionEngine.suggest("perc", languageTag = "it-IT", lexicon = lexicon)
                .first().text,
        )
        assertEquals(
            "l’ho",
            SuggestionEngine.suggest("l'h", languageTag = "it-IT", lexicon = lexicon)
                .first().text,
        )
        assertEquals(
            "c’è",
            SuggestionEngine.suggest("c’", languageTag = "it-IT", lexicon = lexicon)
                .first().text,
        )
    }
}
