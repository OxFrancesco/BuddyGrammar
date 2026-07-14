package com.francescooddo.buddygrammar.core

/** Shared language normalization for local text intelligence and personalization. */
object LanguageSupport {
    const val DEFAULT_LANGUAGE_TAG = "en"

    fun preferredTag(editorHintTags: List<String>, deviceTags: List<String>): String =
        (editorHintTags.asSequence() + deviceTags.asSequence())
            .map(String::trim)
            .firstOrNull(String::isNotEmpty)
            ?: DEFAULT_LANGUAGE_TAG

    /** Groups regional variants so learned language habits follow the user across locales. */
    fun scope(languageTag: String?): String {
        val primary = languageTag
            ?.trim()
            ?.replace('_', '-')
            ?.substringBefore('-')
            ?.lowercase()
            .orEmpty()
        val valid = primary.takeIf { it.length in 2..8 && it.all(Char::isLetter) }
            ?: return DEFAULT_LANGUAGE_TAG
        return ISO_639_2_TO_1[valid] ?: valid
    }

    fun usesEnglishPriors(languageTag: String?): Boolean =
        scope(languageTag) == DEFAULT_LANGUAGE_TAG

    private val ISO_639_2_TO_1 = mapOf(
        "ara" to "ar",
        "deu" to "de",
        "eng" to "en",
        "fra" to "fr",
        "hin" to "hi",
        "ita" to "it",
        "jpn" to "ja",
        "kor" to "ko",
        "nld" to "nl",
        "pol" to "pl",
        "por" to "pt",
        "rus" to "ru",
        "spa" to "es",
        "tur" to "tr",
        "ukr" to "uk",
        "zho" to "zh",
    )
}
