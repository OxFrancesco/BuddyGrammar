package com.francescooddo.buddygrammar.core

import kotlin.math.abs
import kotlin.math.hypot

/**
 * Conservative on-device typo correction with cheaper costs for transposed
 * letters and adjacent QWERTY keys.
 */
object LocalWordCorrector {
    fun bestCorrection(typedWord: String, candidates: Iterable<String> = WordList.words): String? {
        val source = typedWord.lowercase()
        if (source.length < 2) return null
        val maximumLengthDelta = if (source.length >= 6) 2 else 1
        val seen = HashSet<String>()
        var best: RankedCandidate? = null
        var runnerUp: RankedCandidate? = null

        for (candidate in candidates) {
            if (candidate.isEmpty() || abs(candidate.length - source.length) > maximumLengthDelta) {
                continue
            }
            val normalizedCandidate = candidate.lowercase()
            if (!seen.add(normalizedCandidate)) continue
            if (normalizedCandidate == source) return null
            // Prefix extensions belong in the completion lane and must never
            // be offered or auto-applied as typo corrections.
            if (normalizedCandidate.startsWith(source)) continue

            val ranked = RankedCandidate(
                word = candidate,
                distance = normalizedDistance(source, normalizedCandidate),
            )
            if (ranked.distance > acceptanceThreshold(maxOf(source.length, candidate.length))) {
                continue
            }
            when {
                best == null || ranked < best -> {
                    runnerUp = best
                    best = ranked
                }
                runnerUp == null || ranked < runnerUp -> runnerUp = ranked
            }
        }

        val winner = best ?: return null
        if (
            runnerUp != null &&
            abs(winner.distance - runnerUp.distance) < MINIMUM_SCORE_MARGIN
        ) return null
        return matchingCapitalization(typedWord, winner.word)
    }

    private fun normalizedDistance(source: String, target: String): Double {
        if (source.isEmpty() || target.isEmpty()) return 1.0

        var twoRowsBack = DoubleArray(target.length + 1)
        var previousRow = DoubleArray(target.length + 1) { index -> index * INSERT_DELETE_COST }
        for (sourceIndex in 1..source.length) {
            val currentRow = DoubleArray(target.length + 1)
            currentRow[0] = sourceIndex * INSERT_DELETE_COST
            for (targetIndex in 1..target.length) {
                val substitution = previousRow[targetIndex - 1] +
                    substitutionCost(source[sourceIndex - 1], target[targetIndex - 1])
                val deletion = previousRow[targetIndex] + INSERT_DELETE_COST
                val insertion = currentRow[targetIndex - 1] + INSERT_DELETE_COST
                var best = minOf(substitution, deletion, insertion)

                if (
                    sourceIndex > 1 && targetIndex > 1 &&
                    source[sourceIndex - 1] == target[targetIndex - 2] &&
                    source[sourceIndex - 2] == target[targetIndex - 1]
                ) {
                    best = minOf(best, twoRowsBack[targetIndex - 2] + TRANSPOSE_COST)
                }
                currentRow[targetIndex] = best
            }
            twoRowsBack = previousRow
            previousRow = currentRow
        }
        return previousRow[target.length] / maxOf(source.length, target.length)
    }

    private data class RankedCandidate(
        val word: String,
        val distance: Double,
    ) : Comparable<RankedCandidate> {
        override fun compareTo(other: RankedCandidate): Int =
            compareValuesBy(this, other, RankedCandidate::distance, { it.word.length }, { it.word })
    }

    private fun substitutionCost(lhs: Char, rhs: Char): Double {
        if (lhs == rhs) return 0.0
        val left = keyPositions[lhs] ?: return 1.0
        val right = keyPositions[rhs] ?: return 1.0
        return if (hypot(left.first - right.first, left.second - right.second) <= 1.3) {
            NEAR_KEY_COST
        } else {
            1.0
        }
    }

    private fun acceptanceThreshold(length: Int): Double = when (length) {
        in 0..3 -> 0.20
        in 4..5 -> 0.34
        else -> 0.40
    }

    private fun matchingCapitalization(source: String, correction: String): String = when {
        source.any(Char::isLetter) && source.all { !it.isLetter() || it.isUpperCase() } ->
            correction.uppercase()
        source.firstOrNull()?.isUpperCase() == true ->
            correction.replaceFirstChar { it.uppercaseChar() }
        else -> correction
    }

    private val keyPositions: Map<Char, Pair<Double, Double>> = buildMap {
        val rows = listOf("qwertyuiop" to 0.0, "asdfghjkl" to 0.25, "zxcvbnm" to 0.75)
        rows.forEachIndexed { rowIndex, (letters, offset) ->
            letters.forEachIndexed { columnIndex, character ->
                put(character, (columnIndex + offset) to rowIndex.toDouble())
            }
        }
    }

    private const val INSERT_DELETE_COST = 0.9
    private const val NEAR_KEY_COST = 0.45
    private const val TRANSPOSE_COST = 0.25
    private const val MINIMUM_SCORE_MARGIN = 0.04
}
