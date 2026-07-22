package com.francescooddo.buddygrammar.core

import java.text.Normalizer
import java.util.Locale

/** A user-visible spelling paired with the ASCII QWERTY path used to score it. */
internal data class SwipeWordForm(
    val display: String,
    val geometry: String,
)

/**
 * Normalizes Italian display words without losing their spelling.
 *
 * Swipe geometry has only the 26 QWERTY key centers, so accents are folded and
 * apostrophes are removed only for [SwipeWordForm.geometry]. Candidates keep
 * their NFC spelling and use U+2019 as the canonical display apostrophe.
 */
internal object SwipeWordNormalizer {
    fun normalize(word: String): SwipeWordForm? {
        val display = Normalizer.normalize(
            buildString(word.length) {
                word.lowercase(Locale.ROOT).forEach { character ->
                    append(if (character in APOSTROPHES) CANONICAL_APOSTROPHE else character)
                }
            },
            Normalizer.Form.NFC,
        )
        if (!DISPLAY_WORD.matches(display)) return null

        val decomposed = Normalizer.normalize(display, Normalizer.Form.NFD)
        val geometry = buildString(decomposed.length) {
            decomposed.forEach { character ->
                when {
                    character == CANONICAL_APOSTROPHE -> Unit
                    Character.getType(character) in COMBINING_MARK_TYPES -> Unit
                    character in 'a'..'z' -> append(character)
                    else -> return null
                }
            }
        }
        return geometry.takeIf { GEOMETRY_WORD.matches(it) }
            ?.let { SwipeWordForm(display = display, geometry = it) }
    }

    private const val CANONICAL_APOSTROPHE = '’'
    private val APOSTROPHES = setOf('\'', '‘', '’', 'ʼ', '＇')
    private val DISPLAY_WORD = Regex("\\p{Ll}+(?:’\\p{Ll}+)*(?:’)?")
    private val GEOMETRY_WORD = Regex("[a-z]{2,}")
    private val COMBINING_MARK_TYPES = setOf(
        Character.NON_SPACING_MARK.toInt(),
        Character.COMBINING_SPACING_MARK.toInt(),
        Character.ENCLOSING_MARK.toInt(),
    )
}
