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

        val candidateWords = candidates
            .asSequence()
            .filter { it.isNotEmpty() }
            .filter { abs(it.length - source.length) <= maximumLengthDelta }
            .distinctBy { it.lowercase() }
            .toList()
        if (candidateWords.any { it.equals(typedWord, ignoreCase = true) }) return null

        val ranked = candidateWords
            .asSequence()
            // Prefix extensions belong in the completion lane and must never
            // be offered or auto-applied as typo corrections.
            .filterNot { it.lowercase().startsWith(source) }
            .map { candidate -> candidate to normalizedDistance(source, candidate.lowercase()) }
            .filter { (candidate, distance) ->
                distance <= acceptanceThreshold(maxOf(source.length, candidate.length))
            }
            .sortedWith(
                compareBy<Pair<String, Double>> { it.second }
                    .thenBy { it.first.length }
                    .thenBy { it.first },
            )
            .toList()
        val best = ranked.firstOrNull() ?: return null
        val runnerUp = ranked.getOrNull(1)
        if (runnerUp != null && abs(best.second - runnerUp.second) < MINIMUM_SCORE_MARGIN) return null
        return matchingCapitalization(typedWord, best.first)
    }

    private fun normalizedDistance(source: String, target: String): Double {
        val lhs = source.toList()
        val rhs = target.toList()
        if (lhs.isEmpty() || rhs.isEmpty()) return 1.0

        val matrix = Array(lhs.size + 1) { DoubleArray(rhs.size + 1) }
        for (index in 0..lhs.size) matrix[index][0] = index * INSERT_DELETE_COST
        for (index in 0..rhs.size) matrix[0][index] = index * INSERT_DELETE_COST

        for (sourceIndex in 1..lhs.size) {
            for (targetIndex in 1..rhs.size) {
                val substitution = matrix[sourceIndex - 1][targetIndex - 1] +
                    substitutionCost(lhs[sourceIndex - 1], rhs[targetIndex - 1])
                val deletion = matrix[sourceIndex - 1][targetIndex] + INSERT_DELETE_COST
                val insertion = matrix[sourceIndex][targetIndex - 1] + INSERT_DELETE_COST
                var best = minOf(substitution, deletion, insertion)

                if (
                    sourceIndex > 1 && targetIndex > 1 &&
                    lhs[sourceIndex - 1] == rhs[targetIndex - 2] &&
                    lhs[sourceIndex - 2] == rhs[targetIndex - 1]
                ) {
                    best = minOf(best, matrix[sourceIndex - 2][targetIndex - 2] + TRANSPOSE_COST)
                }
                matrix[sourceIndex][targetIndex] = best
            }
        }
        return matrix[lhs.size][rhs.size] / maxOf(lhs.size, rhs.size)
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
