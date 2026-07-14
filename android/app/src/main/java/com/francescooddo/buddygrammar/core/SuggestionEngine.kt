package com.francescooddo.buddygrammar.core

/**
 * A suggestion shown in the keyboard strip.
 *
 * @property text the text to commit when tapped
 * @property replaceBeforeCursor how many characters before the cursor to delete first
 * @property appendSpace whether a trailing space should follow the committed text
 * @property isEmoji true when the suggestion replaces a keyword with an emoji
 */
enum class SuggestionKind { CORRECTION, COMPLETION, PREDICTION, EMOJI }

data class Suggestion(
    val text: String,
    val replaceBeforeCursor: Int,
    val appendSpace: Boolean,
    val kind: SuggestionKind = SuggestionKind.COMPLETION,
) {
    val isEmoji: Boolean get() = kind == SuggestionKind.EMOJI
}

/**
 * Pure-Kotlin suggestion engine: prefix completions while typing a word,
 * next-word predictions after a space, and keyword-to-emoji replacements.
 */
object SuggestionEngine {
    const val MAX_SUGGESTIONS = 3

    private val fallbackPredictions = listOf("the", "I", "and", "to", "a")

    private val bigrams: Map<String, List<String>> = mapOf(
        "thank" to listOf("you"),
        "thanks" to listOf("for", "again"),
        "good" to listOf("morning", "luck"),
        "how" to listOf("are", "much"),
        "i" to listOf("am", "will", "think"),
        "see" to listOf("you"),
        "you" to listOf("are", "can"),
        "a" to listOf("lot", "few"),
        "about" to listOf("the", "it"),
        "after" to listOf("the", "that"),
        "all" to listOf("the", "of"),
        "and" to listOf("the", "I"),
        "are" to listOf("you", "not"),
        "as" to listOf("well", "soon"),
        "at" to listOf("the", "least"),
        "be" to listOf("able", "there"),
        "because" to listOf("of", "it"),
        "been" to listOf("a", "so"),
        "before" to listOf("the", "you"),
        "best" to listOf("regards", "of"),
        "but" to listOf("I", "it"),
        "by" to listOf("the", "now"),
        "call" to listOf("me", "you"),
        "can" to listOf("you", "we"),
        "come" to listOf("back", "over"),
        "could" to listOf("you", "be"),
        "did" to listOf("you", "not"),
        "do" to listOf("you", "not"),
        "does" to listOf("not", "it"),
        "for" to listOf("the", "you"),
        "from" to listOf("the", "my"),
        "get" to listOf("the", "back"),
        "give" to listOf("me", "you"),
        "go" to listOf("to", "back"),
        "going" to listOf("to", "on"),
        "got" to listOf("it", "the"),
        "great" to listOf("job", "to"),
        "had" to listOf("a", "to"),
        "happy" to listOf("birthday", "to"),
        "has" to listOf("been", "a"),
        "have" to listOf("a", "you"),
        "having" to listOf("a", "the"),
        "he" to listOf("is", "was"),
        "hear" to listOf("from", "you"),
        "her" to listOf("and", "to"),
        "here" to listOf("is", "are"),
        "his" to listOf("own", "work"),
        "hope" to listOf("you", "to"),
        "if" to listOf("you", "we"),
        "in" to listOf("the", "a"),
        "into" to listOf("the", "a"),
        "is" to listOf("a", "the"),
        "it" to listOf("is", "was"),
        "just" to listOf("a", "wanted"),
        "keep" to listOf("in", "the"),
        "know" to listOf("if", "that"),
        "last" to listOf("night", "week"),
        "let" to listOf("me", "us"),
        "like" to listOf("to", "a"),
        "ll" to listOf("be", "have"),
        "long" to listOf("time", "as"),
        "look" to listOf("at", "forward"),
        "looking" to listOf("forward", "for"),
        "love" to listOf("you", "it"),
        "make" to listOf("sure", "it"),
        "may" to listOf("be", "have"),
        "me" to listOf("know", "a"),
        "miss" to listOf("you"),
        "more" to listOf("than", "of"),
        "much" to listOf("better", "more"),
        "my" to listOf("own", "way"),
        "need" to listOf("to", "a"),
        "next" to listOf("week", "time"),
        "nice" to listOf("to", "day"),
        "no" to listOf("one", "problem"),
        "not" to listOf("sure", "a"),
        "of" to listOf("the", "a"),
        "on" to listOf("the", "my"),
        "one" to listOf("of", "more"),
        "or" to listOf("not", "the"),
        "our" to listOf("own", "team"),
        "out" to listOf("of", "there"),
        "over" to listOf("the", "there"),
        "please" to listOf("let", "send"),
        "right" to listOf("now", "away"),
        "said" to listOf("that", "the"),
        "she" to listOf("is", "was"),
        "should" to listOf("be", "we"),
        "so" to listOf("much", "I"),
        "some" to listOf("of", "time"),
        "sounds" to listOf("good", "great"),
        "take" to listOf("care", "a"),
        "talk" to listOf("to", "soon"),
        "tell" to listOf("me", "you"),
        "than" to listOf("the", "a"),
        "that" to listOf("is", "the"),
        "the" to listOf("best", "same"),
        "their" to listOf("own", "way"),
        "them" to listOf("to", "and"),
        "then" to listOf("I", "we"),
        "there" to listOf("is", "are"),
        "these" to listOf("are", "days"),
        "they" to listOf("are", "will"),
        "this" to listOf("is", "week"),
        "time" to listOf("to", "for"),
        "to" to listOf("be", "the"),
        "up" to listOf("to", "with"),
        "very" to listOf("much", "good"),
        "wait" to listOf("for", "until"),
        "want" to listOf("to", "a"),
        "wanted" to listOf("to", "a"),
        "was" to listOf("a", "not"),
        "we" to listOf("are", "will"),
        "well" to listOf("as", "done"),
        "were" to listOf("not", "you"),
        "what" to listOf("is", "do"),
        "when" to listOf("you", "I"),
        "where" to listOf("is", "the"),
        "which" to listOf("is", "was"),
        "who" to listOf("is", "are"),
        "will" to listOf("be", "you"),
        "with" to listOf("the", "a"),
        "would" to listOf("be", "you"),
        "your" to listOf("own", "time"),
    )

    /**
     * Computes up to [MAX_SUGGESTIONS] suggestions for the text before the
     * cursor, blending the user's own [personal] vocabulary with the static
     * word list and bigram table.
     */
    fun suggest(
        textBeforeCursor: String,
        personal: PersonalLanguageModel? = null,
        languageTag: String = LanguageSupport.DEFAULT_LANGUAGE_TAG,
        suggestionsAllowed: Boolean = true,
    ): List<Suggestion> {
        if (!suggestionsAllowed) return emptyList()
        val currentWord = currentWord(textBeforeCursor)
        return if (currentWord.isNotEmpty()) {
            completionSuggestions(textBeforeCursor, currentWord, personal, languageTag)
        } else {
            predictionSuggestions(textBeforeCursor, personal, languageTag)
        }
    }

    /** True when the next typed letter starts a new sentence. */
    fun isSentenceStart(textBeforeCursor: String): Boolean {
        val trimmed = textBeforeCursor.trimEnd { it.isWhitespace() && it != '\n' }
        return trimmed.isEmpty() || trimmed.last() in SENTENCE_TERMINATORS
    }

    private fun completionSuggestions(
        textBeforeCursor: String,
        currentWord: String,
        personal: PersonalLanguageModel?,
        languageTag: String,
    ): List<Suggestion> {
        val prefix = currentWord.lowercase()
        val usesEnglishPriors = LanguageSupport.usesEnglishPriors(languageTag)
        val personalWords = personal?.completions(prefix, 2, languageTag).orEmpty()
        val staticWords = if (usesEnglishPriors) {
            WordList.words.asSequence()
                .filter { it.length > prefix.length && it.startsWith(prefix) }
                .take(MAX_SUGGESTIONS)
                .toList()
        } else {
            emptyList()
        }
        val completions = (personalWords + staticWords)
            .distinct()
            .take(MAX_SUGGESTIONS)
            .map { matchCase(it, currentWord) }
        val emoji = EmojiSuggestions.emojiFor(currentWord)

        val slots = mutableListOf<Suggestion>()
        val correction = if (
            usesEnglishPriors &&
            (personal?.usageCount(currentWord, languageTag) == 0 || personal == null)
        ) {
            LocalWordCorrector.bestCorrection(currentWord)
        } else {
            null
        }
        correction?.let { word ->
            slots += Suggestion(
                text = matchCase(word, currentWord),
                replaceBeforeCursor = currentWord.length,
                appendSpace = true,
                kind = SuggestionKind.CORRECTION,
            )
        }
        completions.forEach { word ->
            if (slots.any { it.text.equals(word, ignoreCase = true) }) return@forEach
            slots += Suggestion(
                text = word,
                replaceBeforeCursor = currentWord.length,
                appendSpace = true,
                kind = SuggestionKind.COMPLETION,
            )
        }
        if (emoji != null) {
            val emojiSuggestion = Suggestion(
                text = emoji,
                replaceBeforeCursor = currentWord.length,
                appendSpace = false,
                kind = SuggestionKind.EMOJI,
            )
            if (slots.size >= MAX_SUGGESTIONS) {
                slots[MAX_SUGGESTIONS - 1] = emojiSuggestion
            } else {
                slots += emojiSuggestion
            }
        }
        return slots.take(MAX_SUGGESTIONS)
    }

    private fun predictionSuggestions(
        textBeforeCursor: String,
        personal: PersonalLanguageModel?,
        languageTag: String,
    ): List<Suggestion> {
        val trailingWhitespace = textBeforeCursor.takeLastWhile { it.isWhitespace() }
        val beforeWhitespace = textBeforeCursor.dropLast(trailingWhitespace.length)
        val lastWord = currentWord(beforeWhitespace)
        val capitalize = isSentenceStart(textBeforeCursor)

        // The user's own habits outrank the generic bigram table.
        val personalPredictions = personal
            ?.predictions(wordsInCurrentSentence(beforeWhitespace).takeLast(2), 2, languageTag)
            .orEmpty()
        val usesEnglishPriors = LanguageSupport.usesEnglishPriors(languageTag)
        val staticPredictions = if (usesEnglishPriors) {
            bigrams[lastWord.lowercase()].orEmpty()
        } else {
            emptyList()
        }
        val predicted = (personalPredictions + staticPredictions)
            .distinct()
            .take(2)
        val fallbacks = if (usesEnglishPriors) fallbackPredictions else emptyList()
        val words = (predicted + fallbacks)
            .distinctBy { it.lowercase() }
            .take(2)
            .map { word -> if (capitalize) matchCase(word, "X") else word }

        val slots = words.map { word ->
            Suggestion(
                text = word,
                replaceBeforeCursor = 0,
                appendSpace = true,
                kind = SuggestionKind.PREDICTION,
            )
        }.toMutableList()

        if (lastWord.isNotEmpty() && trailingWhitespace.isNotEmpty()) {
            EmojiSuggestions.emojiFor(lastWord)?.let { emoji ->
                slots += Suggestion(
                    text = emoji,
                    replaceBeforeCursor = lastWord.length + trailingWhitespace.length,
                    appendSpace = false,
                    kind = SuggestionKind.EMOJI,
                )
            }
        }
        return slots.take(MAX_SUGGESTIONS)
    }

    private fun currentWord(textBeforeCursor: String): String =
        textBeforeCursor.takeLastWhile { it.isLetterOrDigit() || it == '\'' }

    private fun wordsInCurrentSentence(text: String): List<String> {
        val boundary = text.indexOfLast { it in SENTENCE_TERMINATORS }
        val sentence = text.substring(if (boundary >= 0) boundary + 1 else 0)
        return WORD_PATTERN.findAll(sentence).map { it.value }.toList()
    }

    private fun matchCase(word: String, typed: String): String = when {
        word == "I" -> word
        typed.length > 1 && typed.all { !it.isLetter() || it.isUpperCase() } &&
            typed.any { it.isLetter() } -> word.uppercase()
        typed.firstOrNull()?.isUpperCase() == true ->
            word.replaceFirstChar { it.uppercaseChar() }
        else -> word
    }

    private val SENTENCE_TERMINATORS = setOf('.', '!', '?', '\n', '…')
    private val WORD_PATTERN = Regex("[\\p{L}\\p{N}]+(?:'[\\p{L}\\p{N}]+)*")
}
