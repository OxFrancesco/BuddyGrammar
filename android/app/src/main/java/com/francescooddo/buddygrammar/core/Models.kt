package com.francescooddo.buddygrammar.core

data class BuddySettings(
    val modelId: String = AppConfig.DEFAULT_MODEL,
    val correctionInstruction: String = AppConfig.DEFAULT_CORRECTION_INSTRUCTION.trimIndent(),
    val autoCorrectDictation: Boolean = true,
    val automaticallyCorrectWords: Boolean = true,
    val hasAcceptedCloudProcessing: Boolean = false,
    val hasCompletedOnboarding: Boolean = false,
)

data class PendingTranscript(
    val text: String,
    val createdAtMillis: Long,
    val languageCode: String? = null,
)

internal fun restorePendingTranscript(
    text: String?,
    createdAtMillis: Long,
    languageCode: String?,
): PendingTranscript? {
    val normalizedText = text?.trim().orEmpty()
    if (normalizedText.isEmpty() || createdAtMillis <= 0L) return null
    return PendingTranscript(
        text = normalizedText,
        createdAtMillis = createdAtMillis,
        languageCode = languageCode?.trim()?.takeIf(String::isNotEmpty),
    )
}

data class TranscriptResult(
    val text: String,
    val languageCode: String?,
    val languageProbability: Double?,
)
