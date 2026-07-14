package com.francescooddo.buddygrammar.core

/**
 * Learns language-scoped unigram, bigram, and trigram frequencies from what
 * the user commits so predictions adapt to their vocabulary and context.
 *
 * Counts stay on device: they are serialized through [onPersist] into the
 * IME's private storage and capped with periodic halving so old habits decay.
 */
class PersonalLanguageModel(
    initialData: String? = null,
    private val onPersist: (String) -> Unit = {},
) {
    private val languageModels = mutableMapOf<String, LanguageModel>()
    private var unsavedChanges = 0

    init {
        initialData?.let(::decode)
    }

    fun learn(
        previousWord: String?,
        word: String,
        languageTag: String = LanguageSupport.DEFAULT_LANGUAGE_TAG,
    ) {
        learn(contextWords = listOfNotNull(previousWord), word = word, languageTag = languageTag)
    }

    /** Learns [word] using up to the two most recent words as context. */
    fun learn(
        contextWords: List<String>,
        word: String,
        languageTag: String = LanguageSupport.DEFAULT_LANGUAGE_TAG,
    ) {
        val normalized = normalize(word) ?: return
        val model = modelFor(languageTag)
        model.unigrams[normalized] = (model.unigrams[normalized] ?: 0) + 1
        val normalizedContext = contextWords.mapNotNull(::normalize).takeLast(2)
        normalizedContext.lastOrNull()?.let { previous ->
            val continuations = model.bigrams.getOrPut(previous) { mutableMapOf() }
            continuations[normalized] = (continuations[normalized] ?: 0) + 1
        }
        if (normalizedContext.size == 2) {
            val context = TwoWordContext(normalizedContext[0], normalizedContext[1])
            val continuations = model.trigrams.getOrPut(context) { mutableMapOf() }
            continuations[normalized] = (continuations[normalized] ?: 0) + 1
        }
        enforceLimits(model)
        unsavedChanges += 1
        if (unsavedChanges >= SAVE_INTERVAL) persist()
    }

    /**
     * Learns every word in committed text while resetting context at sentence
     * boundaries. [contextBeforeText] lets pasted, dictated, or recognized text
     * continue the sentence immediately before the insertion point.
     */
    fun learnCommittedText(
        text: String,
        contextBeforeText: String = "",
        languageTag: String = LanguageSupport.DEFAULT_LANGUAGE_TAG,
    ) {
        val context = currentSentenceWords(contextBeforeText).takeLast(2).toMutableList()
        for (token in tokens(text)) {
            if (token.isBoundary) {
                context.clear()
                continue
            }
            learn(context, token.value, languageTag)
            normalize(token.value)?.let { normalized ->
                context += normalized
                while (context.size > 2) context.removeAt(0)
            }
        }
    }

    /** Next words the user has typed after [previousWord], most frequent first. */
    fun predictions(
        previousWord: String?,
        limit: Int,
        languageTag: String = LanguageSupport.DEFAULT_LANGUAGE_TAG,
    ): List<String> {
        return predictions(listOfNotNull(previousWord), limit, languageTag)
    }

    /** Next words for one- or two-word [contextWords], most specific first. */
    fun predictions(
        contextWords: List<String>,
        limit: Int,
        languageTag: String = LanguageSupport.DEFAULT_LANGUAGE_TAG,
    ): List<String> {
        if (limit <= 0) return emptyList()
        val context = contextWords.mapNotNull(::normalize).takeLast(2)
        if (context.isEmpty()) return emptyList()
        val model = languageModels[LanguageSupport.scope(languageTag)] ?: return emptyList()
        val results = mutableListOf<String>()

        fun append(continuations: Map<String, Int>) {
            continuations
                .filterValues { it >= 2 }
                .entries
                .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
                .mapTo(results) { it.key }
        }

        if (context.size == 2) {
            append(model.trigrams[TwoWordContext(context[0], context[1])].orEmpty())
        }
        append(model.bigrams[context.last()].orEmpty())
        return results.distinct().take(limit)
    }

    /** The user's own words starting with [prefix], most used first. */
    fun completions(
        prefix: String,
        limit: Int,
        languageTag: String = LanguageSupport.DEFAULT_LANGUAGE_TAG,
    ): List<String> {
        if (limit <= 0) return emptyList()
        val normalized = normalize(prefix) ?: return emptyList()
        val model = languageModels[LanguageSupport.scope(languageTag)] ?: return emptyList()
        return model.unigrams
            .filter { it.key.length > normalized.length && it.key.startsWith(normalized) && it.value >= 3 }
            .entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .take(limit)
            .map { it.key }
    }

    fun usageCount(
        word: String,
        languageTag: String = LanguageSupport.DEFAULT_LANGUAGE_TAG,
    ): Int {
        val model = languageModels[LanguageSupport.scope(languageTag)] ?: return 0
        return normalize(word)?.let { model.unigrams[it] } ?: 0
    }

    fun persist() {
        if (unsavedChanges == 0) return
        onPersist(encode())
        unsavedChanges = 0
    }

    private fun modelFor(languageTag: String): LanguageModel =
        languageModels.getOrPut(LanguageSupport.scope(languageTag)) { LanguageModel() }

    private fun enforceLimits(model: LanguageModel) {
        if (model.unigrams.size > MAX_UNIGRAMS) {
            // Halve counts so stale vocabulary decays, then drop the zeros.
            val halved = model.unigrams.mapValues { it.value / 2 }.filterValues { it > 0 }
            model.unigrams.clear()
            model.unigrams.putAll(halved)
        }
        if (model.bigrams.size > MAX_BIGRAM_CONTEXTS) {
            val kept = model.bigrams.entries
                .sortedByDescending { it.value.values.sum() }
                .take(MAX_BIGRAM_CONTEXTS / 2)
                .associate { it.key to it.value }
            model.bigrams.clear()
            for ((context, continuations) in kept) model.bigrams[context] = continuations
        }
        if (model.trigrams.size > MAX_TRIGRAM_CONTEXTS) {
            val kept = model.trigrams.entries
                .sortedByDescending { it.value.values.sum() }
                .take(MAX_TRIGRAM_CONTEXTS / 2)
                .associate { it.key to it.value }
            model.trigrams.clear()
            for ((context, continuations) in kept) model.trigrams[context] = continuations
        }
        for ((context, continuations) in model.bigrams) {
            if (continuations.size > MAX_CONTINUATIONS) {
                val kept = continuations.entries
                    .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
                    .take(MAX_CONTINUATIONS)
                    .associate { it.key to it.value }
                model.bigrams[context] = kept.toMutableMap()
            }
        }
        for ((context, continuations) in model.trigrams) {
            if (continuations.size > MAX_CONTINUATIONS) {
                val kept = continuations.entries
                    .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
                    .take(MAX_CONTINUATIONS)
                    .associate { it.key to it.value }
                model.trigrams[context] = kept.toMutableMap()
            }
        }
    }

    private fun encode(): String = buildString {
        for ((language, model) in languageModels.toSortedMap()) {
            val scoped = language != LanguageSupport.DEFAULT_LANGUAGE_TAG
            for ((word, count) in model.unigrams) {
                appendLine(if (scoped) "su $language $word $count" else "u $word $count")
            }
            for ((previous, continuations) in model.bigrams) {
                for ((word, count) in continuations) {
                    appendLine(
                        if (scoped) {
                            "sb $language $previous $word $count"
                        } else {
                            "b $previous $word $count"
                        },
                    )
                }
            }
            for ((context, continuations) in model.trigrams) {
                for ((word, count) in continuations) {
                    appendLine(
                        if (scoped) {
                            "st $language ${context.first} ${context.second} $word $count"
                        } else {
                            "t ${context.first} ${context.second} $word $count"
                        },
                    )
                }
            }
        }
    }

    private fun decode(data: String) {
        for (line in data.lineSequence()) {
            val parts = line.split(' ')
            when {
                parts.size == 3 && parts[0] == "u" ->
                    parts[2].toIntOrNull()?.let {
                        modelFor(LanguageSupport.DEFAULT_LANGUAGE_TAG).unigrams[parts[1]] = it
                    }
                parts.size == 4 && parts[0] == "b" ->
                    parts[3].toIntOrNull()?.let {
                        modelFor(LanguageSupport.DEFAULT_LANGUAGE_TAG)
                            .bigrams.getOrPut(parts[1]) { mutableMapOf() }[parts[2]] = it
                    }
                parts.size == 5 && parts[0] == "t" ->
                    parts[4].toIntOrNull()?.let {
                        val context = TwoWordContext(parts[1], parts[2])
                        modelFor(LanguageSupport.DEFAULT_LANGUAGE_TAG)
                            .trigrams.getOrPut(context) { mutableMapOf() }[parts[3]] = it
                    }
                parts.size == 4 && parts[0] == "su" ->
                    parts[3].toIntOrNull()?.let {
                        modelFor(parts[1]).unigrams[parts[2]] = it
                    }
                parts.size == 5 && parts[0] == "sb" ->
                    parts[4].toIntOrNull()?.let {
                        modelFor(parts[1]).bigrams
                            .getOrPut(parts[2]) { mutableMapOf() }[parts[3]] = it
                    }
                parts.size == 6 && parts[0] == "st" ->
                    parts[5].toIntOrNull()?.let {
                        val context = TwoWordContext(parts[2], parts[3])
                        modelFor(parts[1]).trigrams
                            .getOrPut(context) { mutableMapOf() }[parts[4]] = it
                    }
            }
        }
    }

    private fun normalize(word: String): String? {
        val trimmed = word.lowercase()
        val isWord = trimmed.isNotEmpty() &&
            trimmed.length <= MAX_WORD_LENGTH &&
            trimmed.any { it.isLetter() } &&
            trimmed.all { it.isLetter() || it == '\'' }
        return if (isWord) trimmed else null
    }

    private data class TwoWordContext(val first: String, val second: String)

    private data class LanguageModel(
        val unigrams: MutableMap<String, Int> = mutableMapOf(),
        val bigrams: MutableMap<String, MutableMap<String, Int>> = mutableMapOf(),
        val trigrams: MutableMap<TwoWordContext, MutableMap<String, Int>> = mutableMapOf(),
    )

    private data class Token(val value: String, val isBoundary: Boolean)

    private fun currentSentenceWords(text: String): List<String> {
        val words = mutableListOf<String>()
        for (token in tokens(text)) {
            if (token.isBoundary) {
                words.clear()
            } else {
                normalize(token.value)?.let(words::add)
            }
        }
        return words
    }

    private fun tokens(text: String): Sequence<Token> = TOKEN_PATTERN.findAll(text).map { match ->
        val value = match.value
        Token(value = value, isBoundary = value.any { it in SENTENCE_BOUNDARIES })
    }

    private companion object {
        const val MAX_UNIGRAMS = 3_000
        const val MAX_BIGRAM_CONTEXTS = 1_500
        const val MAX_TRIGRAM_CONTEXTS = 2_000
        const val MAX_CONTINUATIONS = 6
        const val SAVE_INTERVAL = 20
        const val MAX_WORD_LENGTH = 24
        val SENTENCE_BOUNDARIES = setOf('.', '!', '?', '\n', '…')
        val TOKEN_PATTERN = Regex("[\\p{L}]+(?:'[\\p{L}]+)*|[.!?…\\n]+")
    }
}
