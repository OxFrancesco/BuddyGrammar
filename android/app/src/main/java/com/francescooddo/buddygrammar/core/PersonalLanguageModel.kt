package com.francescooddo.buddygrammar.core

/**
 * Learns the user's own unigram and bigram frequencies from what they type
 * so predictions and completions adapt to their vocabulary over time.
 *
 * Counts stay on device: they are serialized through [onPersist] into the
 * IME's private storage and capped with periodic halving so old habits decay.
 */
class PersonalLanguageModel(
    initialData: String? = null,
    private val onPersist: (String) -> Unit = {},
) {
    private val unigrams = mutableMapOf<String, Int>()
    private val bigrams = mutableMapOf<String, MutableMap<String, Int>>()
    private var unsavedChanges = 0

    init {
        initialData?.let(::decode)
    }

    fun learn(previousWord: String?, word: String) {
        val normalized = normalize(word) ?: return
        unigrams[normalized] = (unigrams[normalized] ?: 0) + 1
        previousWord?.let(::normalize)?.let { previous ->
            val continuations = bigrams.getOrPut(previous) { mutableMapOf() }
            continuations[normalized] = (continuations[normalized] ?: 0) + 1
        }
        enforceLimits()
        unsavedChanges += 1
        if (unsavedChanges >= SAVE_INTERVAL) persist()
    }

    /** Next words the user has typed after [previousWord], most frequent first. */
    fun predictions(previousWord: String?, limit: Int): List<String> {
        if (limit <= 0) return emptyList()
        val previous = previousWord?.let(::normalize) ?: return emptyList()
        return bigrams[previous].orEmpty()
            .filterValues { it >= 2 }
            .entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .take(limit)
            .map { it.key }
    }

    /** The user's own words starting with [prefix], most used first. */
    fun completions(prefix: String, limit: Int): List<String> {
        if (limit <= 0) return emptyList()
        val normalized = normalize(prefix) ?: return emptyList()
        return unigrams
            .filter { it.key.length > normalized.length && it.key.startsWith(normalized) && it.value >= 3 }
            .entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .take(limit)
            .map { it.key }
    }

    fun persist() {
        if (unsavedChanges == 0) return
        onPersist(encode())
        unsavedChanges = 0
    }

    private fun enforceLimits() {
        if (unigrams.size > MAX_UNIGRAMS) {
            // Halve counts so stale vocabulary decays, then drop the zeros.
            val halved = unigrams.mapValues { it.value / 2 }.filterValues { it > 0 }
            unigrams.clear()
            unigrams.putAll(halved)
        }
        if (bigrams.size > MAX_BIGRAM_CONTEXTS) {
            val kept = bigrams.entries
                .sortedByDescending { it.value.values.sum() }
                .take(MAX_BIGRAM_CONTEXTS / 2)
                .associate { it.key to it.value }
            bigrams.clear()
            for ((context, continuations) in kept) bigrams[context] = continuations
        }
        for ((context, continuations) in bigrams) {
            if (continuations.size > MAX_CONTINUATIONS) {
                val kept = continuations.entries
                    .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
                    .take(MAX_CONTINUATIONS)
                    .associate { it.key to it.value }
                bigrams[context] = kept.toMutableMap()
            }
        }
    }

    private fun encode(): String = buildString {
        for ((word, count) in unigrams) appendLine("u $word $count")
        for ((previous, continuations) in bigrams) {
            for ((word, count) in continuations) appendLine("b $previous $word $count")
        }
    }

    private fun decode(data: String) {
        for (line in data.lineSequence()) {
            val parts = line.split(' ')
            when {
                parts.size == 3 && parts[0] == "u" ->
                    parts[2].toIntOrNull()?.let { unigrams[parts[1]] = it }
                parts.size == 4 && parts[0] == "b" ->
                    parts[3].toIntOrNull()?.let {
                        bigrams.getOrPut(parts[1]) { mutableMapOf() }[parts[2]] = it
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

    private companion object {
        const val MAX_UNIGRAMS = 3_000
        const val MAX_BIGRAM_CONTEXTS = 1_500
        const val MAX_CONTINUATIONS = 6
        const val SAVE_INTERVAL = 20
        const val MAX_WORD_LENGTH = 24
    }
}
