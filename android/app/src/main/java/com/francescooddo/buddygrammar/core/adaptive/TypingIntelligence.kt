package com.francescooddo.buddygrammar.core.adaptive

import java.util.Locale
import kotlin.math.exp
import kotlin.math.ln

/** A tap in fixed QWERTY key units: ten units wide and three units high. */
data class TapPoint(
    val x: Double,
    val y: Double,
) {
    init {
        require(x.isFinite() && y.isFinite()) { "Tap coordinates must be finite" }
    }
}

enum class TypingPolicy {
    /** Population geometry plus curated context, without personal calibration. */
    GENERIC,
    /** Uses an existing personal profile but never mutates it. */
    READ_ONLY,
    /** Uses the profile and accepts only explicit retype feedback. */
    LEARNING,
    /** Uses the profile and accepts known-target practice or explicit retypes. */
    PRACTICE,
    /** Bypasses context and personalization. */
    LITERAL,
    /** Same resolver behavior as literal mode and never records feedback. */
    SENSITIVE,
}

data class TypingContext(
    val currentWordPrefix: String = "",
    val languageTag: String = "en",
    val policy: TypingPolicy = TypingPolicy.GENERIC,
)

data class KeyResolution(
    val character: Char,
    val literalCharacter: Char,
    val confidence: Double,
    val candidates: List<KeyCandidate>,
) {
    val wasAdapted: Boolean get() = character != literalCharacter
}

data class KeyCandidate(
    val character: Char,
    val confidence: Double,
)

enum class OutcomeEvidence {
    PRACTICE_TARGET,
    EXPLICIT_RETYPE,
    DECODER_OUTPUT,
}

data class TypingOutcome(
    val tap: TapPoint,
    val intendedCharacter: Char,
    val evidence: OutcomeEvidence,
    val policy: TypingPolicy = TypingPolicy.GENERIC,
)

/** Safe persistence value: aggregate calibration only, never text or tap history. */
data class TypingProfileSnapshot(
    val version: Int = CURRENT_PROFILE_VERSION,
    val observationCount: Int = 0,
    val meanOffsetX: Double = 0.0,
    val meanOffsetY: Double = 0.0,
) {
    companion object {
        const val CURRENT_PROFILE_VERSION = 1
    }
}

/**
 * Resolves taps against a stable visual QWERTY layout. Language context may
 * claim only ambiguous borders between adjacent keys; every key keeps a
 * literal central anchor.
 */
class TypingIntelligence(
    initialProfile: TypingProfileSnapshot = TypingProfileSnapshot(),
) {
    private var observationCount = initialProfile
        .takeIf { it.version == TypingProfileSnapshot.CURRENT_PROFILE_VERSION }
        ?.observationCount
        ?.coerceIn(0, MAX_PROFILE_OBSERVATIONS)
        ?: 0
    private var meanOffsetX = initialProfile
        .takeIf { it.version == TypingProfileSnapshot.CURRENT_PROFILE_VERSION && it.meanOffsetX.isFinite() }
        ?.meanOffsetX
        ?.coerceIn(-MAX_ABS_OBSERVED_OFFSET, MAX_ABS_OBSERVED_OFFSET)
        ?: 0.0
    private var meanOffsetY = initialProfile
        .takeIf { it.version == TypingProfileSnapshot.CURRENT_PROFILE_VERSION && it.meanOffsetY.isFinite() }
        ?.meanOffsetY
        ?.coerceIn(-MAX_ABS_OBSERVED_OFFSET, MAX_ABS_OBSERVED_OFFSET)
        ?: 0.0

    fun resolve(
        tap: TapPoint,
        context: TypingContext = TypingContext(),
    ): KeyResolution {
        val literalKey = QwertyGeometry.nearest(tap)
        if (context.policy == TypingPolicy.LITERAL ||
            context.policy == TypingPolicy.SENSITIVE ||
            literalKey.containsAnchor(tap)
        ) {
            return literal(literalKey)
        }

        val usesPersonalProfile = context.policy != TypingPolicy.GENERIC &&
            observationCount >= MIN_PERSONAL_OBSERVATIONS
        val calibratedTap = if (usesPersonalProfile) {
            TapPoint(x = tap.x - meanOffsetX, y = tap.y - meanOffsetY)
        } else {
            tap
        }
        val priors = PrefixPriors.forContext(context)
        val candidateKeys = QwertyGeometry.adjacentTo(literalKey)
        val rankedPriors = priors?.let { values ->
            candidateKeys
                .map { it to (values[it.character] ?: PRIOR_FLOOR) }
                .sortedByDescending { it.second }
        }
        val hasStrongPrior = rankedPriors?.let { rankedValues ->
            val strongestPrior = rankedValues.first().second
            val runnerUpPrior = rankedValues.getOrNull(1)?.second ?: PRIOR_FLOOR
            strongestPrior >= MIN_STRONG_PRIOR && strongestPrior - runnerUpPrior >= MIN_PRIOR_MARGIN
        } == true
        if (!hasStrongPrior && !usesPersonalProfile) {
            return literal(literalKey)
        }

        val ranked = candidateKeys
            .map { key ->
                val spatialLogLikelihood =
                    -key.squaredDistanceTo(calibratedTap) / (2.0 * SPATIAL_SIGMA * SPATIAL_SIGMA)
                val languageLogLikelihood = if (hasStrongPrior) {
                    ln(priors[key.character] ?: PRIOR_FLOOR) * LANGUAGE_WEIGHT
                } else {
                    0.0
                }
                key to spatialLogLikelihood + languageLogLikelihood
            }
            .sortedByDescending { it.second }
        val winner = ranked.first()
        val runnerUp = ranked.getOrNull(1)
        val scoreMargin = winner.second - (runnerUp?.second ?: winner.second)
        if (winner.first == literalKey || scoreMargin < MIN_SCORE_MARGIN) return literal(literalKey)

        val rankedCandidates = candidatesFrom(ranked)

        return KeyResolution(
            character = winner.first.character,
            literalCharacter = literalKey.character,
            confidence = rankedCandidates.first().confidence,
            candidates = rankedCandidates,
        )
    }

    fun observe(outcome: TypingOutcome) {
        val isAcceptedEvidence = when (outcome.evidence) {
            OutcomeEvidence.PRACTICE_TARGET -> outcome.policy == TypingPolicy.PRACTICE
            OutcomeEvidence.EXPLICIT_RETYPE ->
                outcome.policy == TypingPolicy.LEARNING || outcome.policy == TypingPolicy.PRACTICE
            OutcomeEvidence.DECODER_OUTPUT -> false
        }
        if (!isAcceptedEvidence) return
        val intendedKey = QwertyGeometry.keyFor(outcome.intendedCharacter) ?: return
        val offsetX = (outcome.tap.x - intendedKey.centerX)
            .coerceIn(-MAX_ABS_OBSERVED_OFFSET, MAX_ABS_OBSERVED_OFFSET)
        val offsetY = (outcome.tap.y - intendedKey.centerY)
            .coerceIn(-MAX_ABS_OBSERVED_OFFSET, MAX_ABS_OBSERVED_OFFSET)
        val nextCount = (observationCount + 1).coerceAtMost(MAX_PROFILE_OBSERVATIONS)
        val learningRate = 1.0 / nextCount
        meanOffsetX += (offsetX - meanOffsetX) * learningRate
        meanOffsetY += (offsetY - meanOffsetY) * learningRate
        observationCount = nextCount
    }

    fun snapshot(): TypingProfileSnapshot = TypingProfileSnapshot(
        observationCount = observationCount,
        meanOffsetX = meanOffsetX,
        meanOffsetY = meanOffsetY,
    )

    private fun literal(key: QwertyKey) = KeyResolution(
        character = key.character,
        literalCharacter = key.character,
        confidence = 1.0,
        candidates = listOf(KeyCandidate(key.character, 1.0)),
    )

    private fun candidatesFrom(ranked: List<Pair<QwertyKey, Double>>): List<KeyCandidate> {
        val maximum = ranked.maxOf { it.second }
        val weights = ranked.map { (key, score) -> key to exp(score - maximum) }
        val selected = weights.take(MAX_CANDIDATES)
        val total = selected.sumOf { it.second }
        return selected
            .map { (key, weight) -> KeyCandidate(key.character, weight / total) }
    }

    private companion object {
        const val PRIOR_FLOOR = 0.01
        const val MIN_STRONG_PRIOR = 0.60
        const val MIN_PRIOR_MARGIN = 0.25
        const val MIN_SCORE_MARGIN = 0.35
        const val SPATIAL_SIGMA = 0.48
        const val LANGUAGE_WEIGHT = 0.85
        const val MAX_ABS_OBSERVED_OFFSET = 0.50
        const val MAX_PROFILE_OBSERVATIONS = 10_000
        const val MIN_PERSONAL_OBSERVATIONS = 5
        const val MAX_CANDIDATES = 5
    }
}

private data class QwertyKey(
    val character: Char,
    val centerX: Double,
    val centerY: Double,
) {
    fun squaredDistanceTo(point: TapPoint): Double {
        val dx = point.x - centerX
        val dy = point.y - centerY
        return dx * dx + dy * dy
    }

    fun squaredDistanceTo(other: QwertyKey): Double {
        val dx = other.centerX - centerX
        val dy = other.centerY - centerY
        return dx * dx + dy * dy
    }

    fun containsAnchor(point: TapPoint): Boolean =
        kotlin.math.abs(point.x - centerX) <= 0.24 &&
            kotlin.math.abs(point.y - centerY) <= 0.32
}

private object QwertyGeometry {
    private val keys = buildList {
        addRow("qwertyuiop", firstCenterX = 0.5, centerY = 0.5)
        addRow("asdfghjkl", firstCenterX = 1.0, centerY = 1.5)
        addRow("zxcvbnm", firstCenterX = 2.0, centerY = 2.5)
    }

    fun nearest(point: TapPoint): QwertyKey = keys.minBy { it.squaredDistanceTo(point) }

    fun keyFor(character: Char): QwertyKey? = keys.firstOrNull {
        it.character == character.lowercaseChar()
    }

    fun adjacentTo(key: QwertyKey): List<QwertyKey> =
        keys.filter { candidate -> candidate == key || candidate.squaredDistanceTo(key) <= 1.46 }

    private fun MutableList<QwertyKey>.addRow(
        characters: String,
        firstCenterX: Double,
        centerY: Double,
    ) {
        characters.forEachIndexed { index, character ->
            add(QwertyKey(character, firstCenterX + index, centerY))
        }
    }
}

private object PrefixPriors {
    private val english = mapOf(
        "hom" to mapOf('e' to 0.92, 'i' to 0.03),
        "th" to mapOf('e' to 0.72, 'a' to 0.08, 'i' to 0.08, 'o' to 0.06),
        "rea" to mapOf('d' to 0.62, 'l' to 0.14, 'c' to 0.08),
        "co" to mapOf('m' to 0.42, 'n' to 0.42),
    )

    fun forContext(context: TypingContext): Map<Char, Double>? {
        if (!context.languageTag.lowercase(Locale.ROOT).startsWith("en")) return null
        val prefix = context.currentWordPrefix
            .lowercase(Locale.ROOT)
            .takeLastWhile { it in 'a'..'z' }
        return english[prefix]
    }
}
