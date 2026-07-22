package com.francescooddo.buddygrammar.core

import java.util.Locale

/** Parser for ranked, QWERTY-swipe-compatible lexicon assets. */
object SwipeLexicon {
    fun parse(source: String): List<String> {
        val words = mutableListOf<String>()
        val seen = mutableSetOf<String>()
        source.lineSequence().forEachIndexed { index, rawLine ->
            val line = rawLine.trim()
            if (line.isEmpty() || line.startsWith('#')) return@forEachIndexed
            require(line == line.lowercase(Locale.ROOT)) {
                "Swipe lexicon line ${index + 1} must be lowercase: $line"
            }
            val form = requireNotNull(SwipeWordNormalizer.normalize(line)) {
                "Swipe lexicon line ${index + 1} must be one swipeable word with letters and internal apostrophes: $line"
            }
            require(seen.add(form.display)) {
                "Swipe lexicon line ${index + 1} repeats ${form.display}"
            }
            words += form.display
        }
        return words
    }
}

object SwipeVocabulary {
    fun productionEngine(lexicon: RankedLanguageLexicon): SwipeTypingEngine = SwipeTypingEngine(
        words = emptyList(),
        languageWords = mapOf(
            "en" to lexicon.words("en"),
            "it" to lexicon.words("it"),
        ),
    )

    /** Compatibility seam retained for focused parser tests. */
    fun productionEngine(italianSource: String): SwipeTypingEngine = productionEngine(
        RankedLanguageLexicon(
            mapOf(
                "en" to WordList.words,
                "it" to SwipeLexicon.parse(italianSource),
            ),
        ),
    )
}
