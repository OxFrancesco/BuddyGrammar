package com.francescooddo.buddygrammar.core

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/** A point in normalized QWERTY key-space, where adjacent keys are one unit apart. */
data class SwipePoint(val x: Double, val y: Double)

/** Monotonic timed sample; milliseconds match the shared Swift/Kotlin traces. */
data class SwipePathSample(
    val x: Double,
    val y: Double,
    val timestampMilliseconds: Double,
) {
    val point: SwipePoint get() = SwipePoint(x, y)
}

data class SwipeDwellConfiguration(
    val minimumMilliseconds: Double,
    val minimumSamples: Int,
    val maximumDriftKeyUnits: Double,
) {
    companion object {
        /** Mirrors the validated keyboard catalog v1 values. */
        val CONTRACT_V1 = SwipeDwellConfiguration(
            minimumMilliseconds = 180.0,
            minimumSamples = 3,
            maximumDriftKeyUnits = 0.42,
        )
    }
}

data class SwipeCandidate(
    val word: String,
    val confidence: Double,
)

enum class SwipeAbstentionReason {
    TOO_SHORT,
    INVALID_SAMPLES,
    NO_CANDIDATE,
    LOW_CONFIDENCE,
    AMBIGUOUS,
}

data class SwipeRecognitionResult(
    val candidates: List<SwipeCandidate>,
    val acceptedCandidate: SwipeCandidate?,
    val confidence: Double,
    val margin: Double,
    val abstentionReason: SwipeAbstentionReason?,
) {
    val abstained: Boolean get() = acceptedCandidate == null

    companion object {
        fun abstaining(reason: SwipeAbstentionReason) = SwipeRecognitionResult(
            candidates = emptyList(),
            acceptedCandidate = null,
            confidence = 0.0,
            margin = 0.0,
            abstentionReason = reason,
        )
    }
}

/** Fixed QWERTY key centers shared by gesture capture and recognition. */
object QwertyKeyLayout {
    private val positions: Map<Char, SwipePoint> = buildMap {
        listOf(
            Triple("qwertyuiop", 0.0, 0.0),
            Triple("asdfghjkl", 0.25, 1.0),
            Triple("zxcvbnm", 0.75, 2.0),
        ).forEach { (row, offset, y) ->
            row.forEachIndexed { index, character ->
                put(character, SwipePoint(index + offset, y))
            }
        }
    }

    fun center(character: Char): SwipePoint? = positions[character.lowercaseChar()]

    fun nearestKey(point: SwipePoint, maximumDistance: Double = 0.8): Char? = positions
        .map { (key, center) -> key to hypot(center.x - point.x, center.y - point.y) }
        .filter { (_, distance) -> distance <= maximumDistance }
        .minByOrNull { (_, distance) -> distance }
        ?.first
}

/**
 * SHARK²-style swipe recognizer matching the iOS keyboard implementation.
 *
 * The captured gesture and each candidate word are resampled into equal-length
 * paths. Absolute location, translation/scale-independent shape, word rank,
 * and sentence context are blended into one rejection score.
 */
class SwipeTypingEngine(
    words: List<String> = WordList.words,
    languageWords: Map<String, List<String>> = emptyMap(),
    private val dwellConfiguration: SwipeDwellConfiguration = SwipeDwellConfiguration.CONTRACT_V1,
) {
    private data class Entry(
        val word: String,
        val geometry: String,
        val rank: Int,
        val languageTag: String?,
        val centers: List<SwipePoint>,
        val repeatedLetters: Map<Char, Int>,
        val pathLength: Double,
        val firstCenter: SwipePoint,
        val lastCenter: SwipePoint,
    )

    private data class WordSource(
        val word: String,
        val rank: Int,
        val languageTag: String?,
    )

    private data class ScoredEntry(
        val word: String,
        val score: Double,
    )

    private data class KeyRun(
        val key: Char,
        val samples: MutableList<SwipePathSample>,
    )

    private val entries: List<Entry>

    init {
        val sources = words.mapIndexed { rank, word ->
            WordSource(word = word, rank = rank, languageTag = null)
        }.toMutableList()
        languageWords.toSortedMap().forEach { (languageTag, taggedWords) ->
            val baseRank = sources.size
            taggedWords.forEachIndexed { index, word ->
                sources += WordSource(
                    word = word,
                    rank = baseRank + index,
                    languageTag = baseLanguage(languageTag),
                )
            }
        }

        val seen = mutableSetOf<String>()
        entries = sources.mapNotNull { source ->
            val form = SwipeWordNormalizer.normalize(source.word) ?: return@mapNotNull null
            val word = form.display
            val geometry = form.geometry
            if (
                !seen.add("${source.languageTag ?: "*"}|$word")
            ) {
                return@mapNotNull null
            }

            val centers = mutableListOf<SwipePoint>()
            var previous: Char? = null
            geometry.forEach { letter ->
                if (letter != previous) {
                    centers += QwertyKeyLayout.center(letter) ?: return@mapNotNull null
                }
                previous = letter
            }
            val first = centers.firstOrNull() ?: return@mapNotNull null
            val last = centers.last()

            val repeatedLetters = mutableMapOf<Char, Int>()
            previous = null
            geometry.forEach { letter ->
                if (letter == previous) {
                    repeatedLetters[letter] = repeatedLetters.getOrDefault(letter, 0) + 1
                }
                previous = letter
            }

            Entry(
                word = word,
                geometry = geometry,
                rank = source.rank,
                languageTag = source.languageTag,
                centers = centers,
                repeatedLetters = repeatedLetters,
                pathLength = length(centers),
                firstCenter = first,
                lastCenter = last,
            )
        }
    }

    fun candidates(
        trace: String,
        limit: Int = 3,
        previousWord: String? = null,
    ): List<String> = candidates(
        path = trace.mapNotNull(QwertyKeyLayout::center),
        limit = limit,
        previousWord = previousWord,
    )

    fun candidates(
        path: List<SwipePoint>,
        limit: Int = 3,
        previousWord: String? = null,
    ): List<String> = scoredCandidates(
        path = path,
        repeatedLetters = null,
        limit = limit,
        previousWord = previousWord,
        languageTag = null,
    )
        .filter { it.score <= REJECTION_SCORE }
        .map(ScoredEntry::word)

    /**
     * Rich timed recognition Interface. Candidate confidences and the top-two
     * margin are returned even when recognition conservatively abstains.
     */
    fun recognize(
        samples: List<SwipePathSample>,
        limit: Int = 3,
        previousWord: String? = null,
        languageTag: String? = null,
    ): SwipeRecognitionResult {
        if (samples.size < 2 || limit <= 0) {
            return SwipeRecognitionResult.abstaining(SwipeAbstentionReason.TOO_SHORT)
        }
        if (!valid(samples)) {
            return SwipeRecognitionResult.abstaining(SwipeAbstentionReason.INVALID_SAMPLES)
        }

        val scored = scoredCandidates(
            path = samples.map(SwipePathSample::point),
            repeatedLetters = repeatedLetterEvidence(samples, dwellConfiguration),
            limit = limit,
            previousWord = previousWord,
            languageTag = languageTag,
        ).filter { it.score <= RECOGNITION_SCORE_LIMIT }
        if (scored.isEmpty()) {
            return SwipeRecognitionResult.abstaining(SwipeAbstentionReason.NO_CANDIDATE)
        }

        val candidates = scored.map { candidate ->
            SwipeCandidate(candidate.word, confidence(candidate.score))
        }
        val confidence = candidates.first().confidence
        val margin = if (candidates.size > 1) {
            max(0.0, confidence - candidates[1].confidence)
        } else {
            confidence
        }
        val reason = when {
            confidence < MINIMUM_CONFIDENCE -> SwipeAbstentionReason.LOW_CONFIDENCE
            margin < MINIMUM_MARGIN -> SwipeAbstentionReason.AMBIGUOUS
            else -> null
        }
        return SwipeRecognitionResult(
            candidates = candidates,
            acceptedCandidate = candidates.firstOrNull().takeIf { reason == null },
            confidence = confidence,
            margin = margin,
            abstentionReason = reason,
        )
    }

    private fun scoredCandidates(
        path: List<SwipePoint>,
        repeatedLetters: Map<Char, Int>?,
        limit: Int,
        previousWord: String?,
        languageTag: String?,
    ): List<ScoredEntry> {
        if (path.size < 2 || limit <= 0 || entries.isEmpty()) return emptyList()
        val start = path.first()
        val end = path.last()
        val requestedLanguage = languageTag?.let(::baseLanguage)
        val eligibleEntries = entries.filter { entry ->
            requestedLanguage == null ||
                entry.languageTag == null ||
                entry.languageTag == requestedLanguage
        }
        val sampledPath = resample(path, SAMPLE_COUNT)
        val sampledShape = shapeNormalized(sampledPath)
        val pathLength = length(path)
        val vocabularySize = max(eligibleEntries.size, 1)
        val continuations = SuggestionEngine.commonContinuations(previousWord)
        val bestByWord = mutableMapOf<String, Double>()

        eligibleEntries.forEach { entry ->
            val startDistance = distance(entry.firstCenter, start)
            val endDistance = distance(entry.lastCenter, end)
            if (
                startDistance > ANCHOR_TOLERANCE ||
                endDistance > ANCHOR_TOLERANCE ||
                abs(ln((entry.pathLength + 0.5) / (pathLength + 0.5))) > ln(2.3)
            ) {
                return@forEach
            }

            val idealPath = resample(entry.centers, SAMPLE_COUNT)
            val location = meanDistance(sampledPath, idealPath) / 3.0
            val shape = meanDistance(sampledShape, shapeNormalized(idealPath)) * 2.0
            val rankScore = ln(1.0 + entry.rank) / ln(1.0 + vocabularySize)
            var score = 0.40 * location.coerceAtMost(1.5) +
                0.32 * shape.coerceAtMost(1.5) +
                0.18 * rankScore +
                0.05 * (startDistance + endDistance)
            if (repeatedLetters != null) {
                score += repeatedLetterScore(
                    expected = entry.repeatedLetters,
                    observed = repeatedLetters,
                )
            }
            if (entry.word in continuations) score -= 0.10
            bestByWord[entry.word] = min(bestByWord[entry.word] ?: Double.POSITIVE_INFINITY, score)
        }

        return bestByWord.map { (word, score) -> ScoredEntry(word, score) }
            .sortedWith(compareBy<ScoredEntry> { it.score }.thenBy { it.word })
            .take(limit)
    }

    private fun repeatedLetterEvidence(
        samples: List<SwipePathSample>,
        configuration: SwipeDwellConfiguration,
    ): Map<Char, Int> {
        val runs = mutableListOf<KeyRun>()
        samples.forEach { sample ->
            val key = QwertyKeyLayout.nearestKey(sample.point) ?: return@forEach
            if (runs.lastOrNull()?.key == key) {
                runs.last().samples += sample
            } else {
                runs += KeyRun(key, mutableListOf(sample))
            }
        }

        val evidence = mutableMapOf<Char, Int>()
        runs.forEach { run ->
            val first = run.samples.firstOrNull() ?: return@forEach
            val last = run.samples.last()
            if (
                run.samples.size < configuration.minimumSamples ||
                last.timestampMilliseconds - first.timestampMilliseconds < configuration.minimumMilliseconds
            ) {
                return@forEach
            }
            val maximumDrift = run.samples.maxOf { sample ->
                hypot(sample.x - first.x, sample.y - first.y)
            }
            if (maximumDrift > configuration.maximumDriftKeyUnits) return@forEach
            evidence[run.key] = evidence.getOrDefault(run.key, 0) + 1
        }
        return evidence
    }

    private fun repeatedLetterScore(
        expected: Map<Char, Int>,
        observed: Map<Char, Int>,
    ): Double = (expected.keys + observed.keys).sumOf { key ->
        val expectedCount = expected.getOrDefault(key, 0)
        val observedCount = observed.getOrDefault(key, 0)
        val matched = min(expectedCount, observedCount)
        val missing = max(0, expectedCount - observedCount)
        val unexpected = max(0, observedCount - expectedCount)
        -0.12 * matched + 0.18 * missing + 0.16 * unexpected
    }

    private fun confidence(score: Double): Double =
        (1.0 / (1.0 + exp(6.0 * (score - 0.45)))).coerceIn(0.0, 1.0)

    private fun baseLanguage(languageTag: String): String = languageTag
        .lowercase()
        .split('-', '_')
        .firstOrNull()
        ?: languageTag.lowercase()

    private fun valid(samples: List<SwipePathSample>): Boolean {
        var previousTimestamp = Double.NEGATIVE_INFINITY
        return samples.all { sample ->
            val valid = sample.x.isFinite() &&
                sample.y.isFinite() &&
                sample.timestampMilliseconds.isFinite() &&
                sample.timestampMilliseconds >= previousTimestamp
            previousTimestamp = sample.timestampMilliseconds
            valid
        }
    }

    private companion object {
        const val SAMPLE_COUNT = 32
        const val ANCHOR_TOLERANCE = 1.6
        const val REJECTION_SCORE = 0.62
        const val RECOGNITION_SCORE_LIMIT = 0.78
        const val MINIMUM_CONFIDENCE = 0.50
        const val MINIMUM_MARGIN = 0.03

        fun distance(left: SwipePoint, right: SwipePoint): Double =
            hypot(left.x - right.x, left.y - right.y)

        fun length(points: List<SwipePoint>): Double = points.zipWithNext()
            .sumOf { (left, right) -> distance(left, right) }

        fun resample(points: List<SwipePoint>, count: Int): List<SwipePoint> {
            val first = points.firstOrNull() ?: return emptyList()
            val total = length(points)
            if (points.size < 2 || total <= 0.0) return List(count) { first }

            val interval = total / (count - 1)
            val result = mutableListOf(first)
            var accumulated = 0.0
            var previous = first
            for (point in points.drop(1)) {
                var segment = distance(previous, point)
                var segmentStart = previous
                while (accumulated + segment >= interval && result.size < count) {
                    val ratio = (interval - accumulated) / segment
                    val sample = SwipePoint(
                        x = segmentStart.x + ratio * (point.x - segmentStart.x),
                        y = segmentStart.y + ratio * (point.y - segmentStart.y),
                    )
                    result += sample
                    segment = accumulated + segment - interval
                    accumulated = 0.0
                    segmentStart = sample
                }
                accumulated += segment
                previous = point
            }
            while (result.size < count) result += points.last()
            return result
        }

        fun shapeNormalized(points: List<SwipePoint>): List<SwipePoint> {
            if (points.isEmpty()) return points
            val centroid = SwipePoint(
                x = points.sumOf(SwipePoint::x) / points.size,
                y = points.sumOf(SwipePoint::y) / points.size,
            )
            val scale = max(
                max(
                    points.maxOf(SwipePoint::x) - points.minOf(SwipePoint::x),
                    points.maxOf(SwipePoint::y) - points.minOf(SwipePoint::y),
                ),
                0.01,
            )
            return points.map { point ->
                SwipePoint((point.x - centroid.x) / scale, (point.y - centroid.y) / scale)
            }
        }

        fun meanDistance(left: List<SwipePoint>, right: List<SwipePoint>): Double {
            if (left.size != right.size || left.isEmpty()) return Double.POSITIVE_INFINITY
            return left.indices.sumOf { distance(left[it], right[it]) } / left.size
        }
    }
}
