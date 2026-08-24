package com.francescooddo.buddygrammar.core.adaptive

import com.francescooddo.buddygrammar.core.LanguageSupport
import com.francescooddo.buddygrammar.core.RankedLanguageLexicon
import com.francescooddo.buddygrammar.core.SuggestionEngine
import com.francescooddo.buddygrammar.core.SuggestionKind
import com.francescooddo.buddygrammar.core.WordTokenNormalizer
import java.util.Locale
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * One position in a word-sized tap lattice. The literal and per-tap resolved
 * keys stay explicit so callers can always recover either conservative path.
 */
data class TapWordLatticeTap(
    val literalKey: Char,
    val resolvedKey: Char,
    val candidates: List<KeyCandidate>,
) {
    constructor(
        resolution: KeyResolution,
        literalTap: Char = resolution.literalCharacter,
    ) : this(
        literalKey = literalTap,
        resolvedKey = resolution.character,
        candidates = resolution.candidates,
    )
}

/** A whole-word hypothesis ranked by bounded spatial and language evidence. */
data class TapWordCandidate(
    val word: String,
    val score: Double,
    val confidence: Double,
    val isLiteralPath: Boolean,
    val isResolvedPath: Boolean,
)

/**
 * Result of ranking a word-sized lattice. [margin] is the normalized
 * confidence gap between the first and second candidates, not an instruction
 * to autocorrect.
 */
data class TapWordDecodingResult(
    val literalWord: String,
    val resolvedWord: String,
    val candidates: List<TapWordCandidate>,
    val margin: Double,
) {
    internal companion object {
        val EMPTY = TapWordDecodingResult(
            literalWord = "",
            resolvedWord = "",
            candidates = emptyList(),
            margin = 0.0,
        )
    }
}

/**
 * Deterministic, bounded beam search over adjacent per-key substitutions.
 * The decoder owns no mutable history and persists neither taps nor text.
 */
class TapWordDecoder(
    private val lexicon: RankedLanguageLexicon = RankedLanguageLexicon.legacyEnglish,
) {
    fun decode(
        taps: List<TapWordLatticeTap>,
        previousWord: String? = null,
        languageTag: String? = null,
        limit: Int = DEFAULT_RESULT_LIMIT,
    ): TapWordDecodingResult {
        if (taps.isEmpty() || taps.size > MAXIMUM_TAPS) return TapWordDecodingResult.EMPTY

        val rows = ArrayList<List<Option>>(taps.size)
        val literalWord = StringBuilder(taps.size)
        val resolvedWord = StringBuilder(taps.size)
        for (tap in taps) {
            val normalizedLiteral = normalizedAscii(tap.literalKey)
                ?: return TapWordDecodingResult.EMPTY
            val options = options(tap, normalizedLiteral)
                ?: return TapWordDecodingResult.EMPTY
            literalWord.append(tap.literalKey)
            resolvedWord.append(safeResolvedKey(tap, normalizedLiteral))
            rows += options
        }

        var beam = listOf(Path(word = "", spatialLogScore = 0.0))
        rows.forEach { options ->
            val expanded = ArrayList<Path>(beam.size * options.size)
            beam.forEach { path ->
                options.forEach { option ->
                    expanded += Path(
                        word = path.word + option.key,
                        spatialLogScore = path.spatialLogScore + ln(option.probability),
                    )
                }
            }
            beam = expanded.sortedWith(PATH_COMPARATOR).take(MAXIMUM_BEAM_WIDTH)
        }

        val literal = literalWord.toString()
        val resolved = resolvedWord.toString()
        val pathsByWord = mutableMapOf<String, Path>()
        beam.forEach { insertBest(it, pathsByWord) }
        insertBest(forcedPath(literal, rows), pathsByWord)
        insertBest(forcedPath(resolved, rows), pathsByWord)

        val requiredWords = setOf(literal, resolved)
        val contextualScores = contextScores(previousWord, languageTag)
        val scoredByWord = mutableMapOf<String, ScoredPath>()
        fun insertScored(candidate: ScoredPath) {
            val existing = scoredByWord[candidate.path.word]
            if (existing == null || SCORED_PATH_COMPARATOR.compare(candidate, existing) < 0) {
                scoredByWord[candidate.path.word] = candidate
            }
        }
        pathsByWord.values.forEach { path ->
            val match = lexicon.match(path.word, languageTag)
            if (match != null) {
                val displayWord = matchingCapitalization(match.display, path.word)
                insertScored(
                    ScoredPath(
                        path = Path(displayWord, path.spatialLogScore),
                        score = path.spatialLogScore + languageScore(match, contextualScores),
                        isLiteral = displayWord == literal,
                        isResolved = displayWord == resolved,
                    ),
                )
                // Canonical spelling is an extra hypothesis. Keep exact
                // literal/resolved anchors available for fallback and undo.
                if (path.word !in requiredWords || displayWord == path.word) {
                    return@forEach
                }
            }
            insertScored(
                ScoredPath(
                    path = path,
                    score = path.spatialLogScore + outOfVocabularyScore(languageTag),
                    isLiteral = path.word == literal,
                    isResolved = path.word == resolved,
                ),
            )
        }
        val scored = scoredByWord.values.sortedWith(SCORED_PATH_COMPARATOR)

        val requestedCount = max(
            requiredWords.size,
            min(limit.coerceAtLeast(1), MAXIMUM_RESULTS),
        )
        val selected = scored.take(requestedCount).toMutableList()
        requiredWords.forEach { requiredWord ->
            if (selected.none { it.path.word == requiredWord }) {
                val forced = scored.firstOrNull { it.path.word == requiredWord }
                    ?: return@forEach
                if (selected.size < requestedCount) {
                    selected += forced
                } else {
                    val removableIndex = selected.indexOfLast {
                        it.path.word !in requiredWords
                    }
                    if (removableIndex >= 0) selected[removableIndex] = forced
                }
            }
        }
        selected.sortWith(SCORED_PATH_COMPARATOR)

        val maximumScore = selected.firstOrNull()?.score
            ?.takeIf(Double::isFinite)
            ?: return literalFallback(literal, resolved)
        val exponentials = selected.map { exp((it.score - maximumScore) / CONFIDENCE_TEMPERATURE) }
        val total = exponentials.sum()
        if (!total.isFinite() || total <= 0.0) return literalFallback(literal, resolved)

        val candidates = selected.zip(exponentials) { path, weight ->
            TapWordCandidate(
                word = path.path.word,
                score = path.score,
                confidence = weight / total,
                isLiteralPath = path.isLiteral,
                isResolvedPath = path.isResolved,
            )
        }
        val firstConfidence = candidates.firstOrNull()?.confidence ?: 0.0
        val secondConfidence = candidates.getOrNull(1)?.confidence ?: 0.0
        return TapWordDecodingResult(
            literalWord = literal,
            resolvedWord = resolved,
            candidates = candidates,
            margin = (firstConfidence - secondConfidence).coerceIn(0.0, 1.0),
        )
    }

    private fun options(
        tap: TapWordLatticeTap,
        normalizedLiteral: Char,
    ): List<Option>? {
        val literalKey = render(normalizedLiteral, tap.literalKey)
        val resolvedKey = safeResolvedKey(tap, normalizedLiteral)
        val normalizedResolved = normalizedAscii(resolvedKey) ?: normalizedLiteral
        val weights = mutableMapOf<Char, Double>()

        // Bound inspection as well as output so malformed candidate lists
        // cannot turn a single tap into unbounded work.
        tap.candidates.take(MAXIMUM_CANDIDATES_PER_TAP * 3).forEach { candidate ->
            val normalizedKey = normalizedAscii(candidate.character)
            if (
                candidate.confidence.isFinite() &&
                candidate.confidence > 0.0 &&
                normalizedKey != null &&
                DecoderQwertyLayout.areAdjacent(normalizedLiteral, normalizedKey)
            ) {
                weights[normalizedKey] = max(weights[normalizedKey] ?: 0.0, candidate.confidence)
            }
        }
        weights[normalizedLiteral] = max(weights[normalizedLiteral] ?: 0.0, ANCHOR_CONFIDENCE_FLOOR)
        weights[normalizedResolved] = max(weights[normalizedResolved] ?: 0.0, ANCHOR_CONFIDENCE_FLOOR)

        val ranked = weights.map { (key, weight) ->
            WeightedKey(
                normalizedKey = key,
                renderedKey = render(key, tap.literalKey),
                weight = weight,
                isLiteral = key == normalizedLiteral,
                isResolved = key == normalizedResolved,
            )
        }.sortedWith(WEIGHTED_KEY_COMPARATOR)

        val requiredKeys = setOf(normalizedLiteral, normalizedResolved)
        val selected = ranked.take(MAXIMUM_CANDIDATES_PER_TAP).toMutableList()
        requiredKeys.forEach { requiredKey ->
            if (selected.none { it.normalizedKey == requiredKey }) {
                val forced = ranked.firstOrNull { it.normalizedKey == requiredKey }
                    ?: return@forEach
                val removableIndex = selected.indexOfLast {
                    it.normalizedKey !in requiredKeys
                }
                if (removableIndex >= 0) selected[removableIndex] = forced
            }
        }
        selected.sortWith(WEIGHTED_KEY_COMPARATOR)

        val total = selected.sumOf { it.weight }
        if (!total.isFinite() || total <= 0.0) return null
        return selected.map { weightedKey ->
            Option(
                key = if (weightedKey.normalizedKey == normalizedLiteral) {
                    literalKey
                } else {
                    weightedKey.renderedKey
                },
                probability = (weightedKey.weight / total).coerceAtLeast(MINIMUM_PROBABILITY),
            )
        }
    }

    private fun safeResolvedKey(tap: TapWordLatticeTap, normalizedLiteral: Char): Char {
        val normalized = normalizedAscii(tap.resolvedKey)
            ?.takeIf { DecoderQwertyLayout.areAdjacent(normalizedLiteral, it) }
            ?: return tap.literalKey
        return render(normalized, tap.literalKey)
    }

    private fun forcedPath(word: String, rows: List<List<Option>>): Path {
        var spatialLogScore = 0.0
        word.forEachIndexed { index, character ->
            val options = rows[index]
            val normalized = normalizedAscii(character)
            val probability = options.firstOrNull {
                normalizedAscii(it.key) == normalized
            }?.probability ?: ANCHOR_CONFIDENCE_FLOOR
            spatialLogScore += ln(probability.coerceAtLeast(MINIMUM_PROBABILITY))
        }
        return Path(word = word, spatialLogScore = spatialLogScore)
    }

    private fun languageScore(
        match: RankedLanguageLexicon.Match,
        contextScores: Map<String, Double>,
    ): Double {
        val normalizedWord = match.display.lowercase(Locale.ROOT)
        var score = max(
            MINIMUM_IN_VOCABULARY_SCORE,
            0.9 - 0.25 * log10(match.rank.toDouble() + 1.0),
        )
        score += contextScores[normalizedWord] ?: 0.0
        return score
    }

    private fun outOfVocabularyScore(languageTag: String?): Double =
        if (lexicon.supports(languageTag)) OUT_OF_VOCABULARY_SCORE else 0.0

    private fun contextScores(
        previousWord: String?,
        languageTag: String?,
    ): Map<String, Double> {
        if (languageTag == null || !LanguageSupport.usesEnglishPriors(languageTag)) {
            return emptyMap()
        }
        val normalizedPrevious = previousWord
            ?.takeLast(MAXIMUM_CONTEXT_CHARACTERS)
            ?.trim()
            ?.takeLastWhile(WordTokenNormalizer::isWordCharacter)
            ?.let(WordTokenNormalizer::canonicalize)
            ?.takeIf(String::isNotEmpty)
            ?: return emptyMap()
        return SuggestionEngine.suggest(
            textBeforeCursor = "$normalizedPrevious ",
            languageTag = languageTag,
            lexicon = lexicon,
        ).asSequence()
            .filter { it.kind == SuggestionKind.PREDICTION }
            .take(CONTEXT_BOOSTS.size)
            .mapIndexed { index, suggestion ->
                suggestion.text.lowercase(Locale.ROOT) to CONTEXT_BOOSTS[index]
            }
            .toMap()
    }

    private data class Option(val key: Char, val probability: Double)
    private data class WeightedKey(
        val normalizedKey: Char,
        val renderedKey: Char,
        val weight: Double,
        val isLiteral: Boolean,
        val isResolved: Boolean,
    )
    private data class Path(val word: String, val spatialLogScore: Double)
    private data class ScoredPath(
        val path: Path,
        val score: Double,
        val isLiteral: Boolean,
        val isResolved: Boolean,
    )

    companion object {
        const val MAXIMUM_TAPS = 32
        const val MAXIMUM_CANDIDATES_PER_TAP = 5
        const val MAXIMUM_BEAM_WIDTH = 48
        const val MAXIMUM_RESULTS = 8

        private const val DEFAULT_RESULT_LIMIT = 5
        private const val ANCHOR_CONFIDENCE_FLOOR = 0.015
        private const val MINIMUM_PROBABILITY = 0.000_000_001
        private const val CONFIDENCE_TEMPERATURE = 1.15
        private const val OUT_OF_VOCABULARY_SCORE = -0.75
        private const val MINIMUM_IN_VOCABULARY_SCORE = -0.2
        private const val COMPARISON_EPSILON = 0.000_000_001
        private const val MAXIMUM_CONTEXT_CHARACTERS = 32
        private val CONTEXT_BOOSTS = listOf(0.9, 0.55, 0.3)

        /** Letter-key sample count for display text after accent/apostrophe folding. */
        fun expectedTapCount(visibleWord: String): Int? =
            WordTokenNormalizer.tapGeometry(visibleWord)?.length

        private val PATH_COMPARATOR = Comparator<Path> { left, right ->
            compareScoresThenWords(
                leftScore = left.spatialLogScore,
                rightScore = right.spatialLogScore,
                leftWord = left.word,
                rightWord = right.word,
            )
        }
        private val WEIGHTED_KEY_COMPARATOR = Comparator<WeightedKey> { left, right ->
            when {
                abs(left.weight - right.weight) > COMPARISON_EPSILON ->
                    right.weight.compareTo(left.weight)
                left.isLiteral != right.isLiteral -> if (left.isLiteral) -1 else 1
                left.isResolved != right.isResolved -> if (left.isResolved) -1 else 1
                else -> left.normalizedKey.compareTo(right.normalizedKey)
            }
        }
        private val SCORED_PATH_COMPARATOR = Comparator<ScoredPath> { left, right ->
            when {
                abs(left.score - right.score) > COMPARISON_EPSILON ->
                    right.score.compareTo(left.score)
                left.isLiteral != right.isLiteral -> if (left.isLiteral) -1 else 1
                left.isResolved != right.isResolved -> if (left.isResolved) -1 else 1
                else -> left.path.word.compareTo(right.path.word)
            }
        }

        private fun compareScoresThenWords(
            leftScore: Double,
            rightScore: Double,
            leftWord: String,
            rightWord: String,
        ): Int = if (abs(leftScore - rightScore) > COMPARISON_EPSILON) {
            rightScore.compareTo(leftScore)
        } else {
            leftWord.compareTo(rightWord)
        }

        private fun normalizedAscii(character: Char): Char? {
            val normalized = character.lowercaseChar()
            return normalized.takeIf { it in 'a'..'z' }
        }

        private fun render(normalized: Char, literal: Char): Char =
            if (literal.isUpperCase()) normalized.uppercaseChar() else normalized

        private fun matchingCapitalization(word: String, typed: String): String = when {
            typed.any(Char::isLetter) && typed.all { !it.isLetter() || it.isUpperCase() } ->
                word.uppercase(Locale.ROOT)
            typed.firstOrNull()?.isUpperCase() == true ->
                word.lowercase(Locale.ROOT).replaceFirstChar(Char::uppercaseChar)
            else -> word
        }

        private fun insertBest(path: Path, paths: MutableMap<String, Path>) {
            val existing = paths[path.word]
            if (existing == null || path.spatialLogScore > existing.spatialLogScore) {
                paths[path.word] = path
            }
        }

        private fun literalFallback(
            literalWord: String,
            resolvedWord: String,
        ) = TapWordDecodingResult(
            literalWord = literalWord,
            resolvedWord = resolvedWord,
            candidates = listOf(
                TapWordCandidate(
                    word = literalWord,
                    score = 0.0,
                    confidence = 1.0,
                    isLiteralPath = true,
                    isResolvedPath = literalWord == resolvedWord,
                ),
            ),
            margin = 1.0,
        )
    }
}

private object DecoderQwertyLayout {
    private const val NEIGHBOR_DISTANCE = 1.3
    private val positions = buildMap {
        addRow("qwertyuiop", horizontalOffset = 0.0, row = 0.0)
        addRow("asdfghjkl", horizontalOffset = 0.25, row = 1.0)
        addRow("zxcvbnm", horizontalOffset = 0.75, row = 2.0)
    }

    fun areAdjacent(left: Char, right: Char): Boolean {
        val leftPosition = positions[left] ?: return false
        val rightPosition = positions[right] ?: return false
        val deltaX = leftPosition.first - rightPosition.first
        val deltaY = leftPosition.second - rightPosition.second
        return sqrt(deltaX * deltaX + deltaY * deltaY) <= NEIGHBOR_DISTANCE
    }

    private fun MutableMap<Char, Pair<Double, Double>>.addRow(
        characters: String,
        horizontalOffset: Double,
        row: Double,
    ) {
        characters.forEachIndexed { index, character ->
            put(character, Pair(index + horizontalOffset, row))
        }
    }
}
