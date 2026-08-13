package com.francescooddo.buddygrammar.core

import java.text.Normalizer
import java.util.Locale

/**
 * Ranked, language-isolated vocabulary shared by taps, swipes, and static
 * completions. Display spelling stays canonical while lookups use ASCII
 * QWERTY geometry, so `perche` can rank and emit `perché`.
 */
class RankedLanguageLexicon(
    languageWords: Map<String, List<String>>,
) {
    data class Match(
        val display: String,
        val geometry: String,
        val rank: Int,
    )

    private val entriesByLanguage: Map<String, List<Match>>
    private val matchesByLanguageAndGeometry: Map<String, Map<String, Match>>
    private val correctionEntriesByLanguageAndLength: Map<String, Map<Int, List<Match>>>

    init {
        val entries = mutableMapOf<String, List<Match>>()
        val matches = mutableMapOf<String, Map<String, Match>>()
        val corrections = mutableMapOf<String, Map<Int, List<Match>>>()
        languageWords.forEach { (rawLanguage, words) ->
            val language = LanguageSupport.scope(rawLanguage)
            val seenDisplay = mutableSetOf<String>()
            val ranked = mutableListOf<Match>()
            val byGeometry = mutableMapOf<String, Match>()
            words.forEach { word ->
                val form = SwipeWordNormalizer.normalize(word) ?: return@forEach
                if (!seenDisplay.add(form.display)) return@forEach
                val entry = Match(form.display, form.geometry, ranked.size)
                ranked += entry
                // Rank order is the deterministic display choice when two
                // accented/elided forms share one ASCII tap geometry.
                byGeometry.putIfAbsent(form.geometry, entry)
            }
            entries[language] = ranked
            matches[language] = byGeometry
            corrections[language] = ranked.groupBy { it.display.length }
        }
        entriesByLanguage = entries
        matchesByLanguageAndGeometry = matches
        correctionEntriesByLanguageAndLength = corrections
    }

    fun supports(languageTag: String?): Boolean =
        entriesByLanguage.containsKey(LanguageSupport.scope(languageTag))

    fun wordCount(languageTag: String?): Int =
        entriesByLanguage[LanguageSupport.scope(languageTag)]?.size ?: 0

    fun words(languageTag: String?): List<String> =
        entriesByLanguage[LanguageSupport.scope(languageTag)].orEmpty().map(Match::display)

    /**
     * Returns only words whose length can pass the typo corrector's first
     * gate. This keeps each key press from copying and scanning the complete
     * production dictionary.
     */
    fun correctionCandidates(word: String, languageTag: String?): Iterable<String> {
        val sourceLength = word.length
        val maximumLengthDelta = if (sourceLength >= 6) 2 else 1
        val entriesByLength =
            correctionEntriesByLanguageAndLength[LanguageSupport.scope(languageTag)].orEmpty()
        return ((sourceLength - maximumLengthDelta).coerceAtLeast(1)..
            sourceLength + maximumLengthDelta)
            .asSequence()
            .flatMap { length -> entriesByLength[length].orEmpty().asSequence() }
            .map(Match::display)
            .asIterable()
    }

    fun match(word: String, languageTag: String?): Match? {
        val geometry = SwipeWordNormalizer.normalize(word)?.geometry ?: return null
        return matchesByLanguageAndGeometry[LanguageSupport.scope(languageTag)]?.get(geometry)
    }

    fun rank(word: String, languageTag: String?): Int? = match(word, languageTag)?.rank

    fun completions(prefix: String, languageTag: String?, limit: Int): List<String> {
        if (limit <= 0) return emptyList()
        val prefixGeometry = prefixGeometry(prefix)?.takeIf(String::isNotEmpty) ?: return emptyList()
        val canonicalTyped = WordTokenNormalizer.canonicalize(prefix.lowercase(Locale.ROOT))
        val requiresApostropheMatch =
            WordTokenNormalizer.CANONICAL_APOSTROPHE in canonicalTyped
        return entriesByLanguage[LanguageSupport.scope(languageTag)]
            .orEmpty()
            .asSequence()
            .filter { entry ->
                (if (requiresApostropheMatch) {
                    entry.display.startsWith(canonicalTyped)
                } else {
                    entry.geometry.startsWith(prefixGeometry)
                }) &&
                    (entry.geometry.length > prefixGeometry.length ||
                        !entry.display.equals(canonicalTyped, ignoreCase = true))
            }
            .map(Match::display)
            .take(limit)
            .toList()
    }

    private fun prefixGeometry(prefix: String): String? {
        val canonical = WordTokenNormalizer.canonicalize(prefix.lowercase(Locale.ROOT))
        if (
            canonical.isEmpty() ||
            canonical.none(Char::isLetter) ||
            canonical.any { !it.isLetter() && it != WordTokenNormalizer.CANONICAL_APOSTROPHE }
        ) return null
        val folded = Normalizer.normalize(canonical, Normalizer.Form.NFD)
            .filterNot { Character.getType(it) in COMBINING_MARK_TYPES }
            .filter { it != WordTokenNormalizer.CANONICAL_APOSTROPHE }
        return folded.takeIf { value -> value.all { it in 'a'..'z' } }
    }

    companion object {
        val legacyEnglish: RankedLanguageLexicon by lazy {
            RankedLanguageLexicon(mapOf("en" to WordList.words))
        }

        fun parse(languageSources: Map<String, String>): RankedLanguageLexicon =
            RankedLanguageLexicon(
                languageSources.mapValues { (_, source) -> SwipeLexicon.parse(source) },
            )

        private val COMBINING_MARK_TYPES = setOf(
            Character.NON_SPACING_MARK.toInt(),
            Character.COMBINING_SPACING_MARK.toInt(),
            Character.ENCLOSING_MARK.toInt(),
        )
    }
}
