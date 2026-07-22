package com.francescooddo.buddygrammar.core

import java.text.Normalizer
import java.util.Locale

/** Canonical word/apostrophe rules shared by completion and learning paths. */
object WordTokenNormalizer {
    const val CANONICAL_APOSTROPHE: Char = '’'
    private val apostrophes = setOf('\'', '‘', '’', 'ʼ', '＇')

    fun isWordCharacter(character: Char): Boolean =
        character.isLetterOrDigit() ||
            character in apostrophes ||
            Character.getType(character) in COMBINING_MARK_TYPES

    fun canonicalize(text: String): String = Normalizer.normalize(
        text.map { character ->
            if (character in apostrophes) CANONICAL_APOSTROPHE else character
        }.joinToString(separator = ""),
        Normalizer.Form.NFC,
    )

    /** Exact editor suffix for deletion, rollback, and correction receipts. */
    fun rawTrailingWord(textBeforeCursor: String): String =
        textBeforeCursor.takeLastWhile(::isWordCharacter)

    fun tapGeometry(text: String): String? {
        val canonical = canonicalize(text.lowercase(Locale.ROOT))
        if (
            canonical.isEmpty() ||
            canonical.none(Char::isLetter) ||
            canonical.any { !it.isLetter() && it != CANONICAL_APOSTROPHE }
        ) return null
        val geometry = Normalizer.normalize(canonical, Normalizer.Form.NFD)
            .filterNot { Character.getType(it) in COMBINING_MARK_TYPES }
            .filter { it != CANONICAL_APOSTROPHE }
        return geometry.takeIf { value ->
            value.isNotEmpty() && value.all { it in 'a'..'z' }
        }
    }

    fun normalizedWord(word: String): String? {
        val normalized = canonicalize(word.lowercase(Locale.ROOT))
        return normalized.takeIf { value ->
            value.isNotEmpty() &&
                value.any(Char::isLetter) &&
                value.all { it.isLetter() || it == CANONICAL_APOSTROPHE }
        }
    }

    private val COMBINING_MARK_TYPES = setOf(
        Character.NON_SPACING_MARK.toInt(),
        Character.COMBINING_SPACING_MARK.toInt(),
        Character.ENCLOSING_MARK.toInt(),
    )
}
