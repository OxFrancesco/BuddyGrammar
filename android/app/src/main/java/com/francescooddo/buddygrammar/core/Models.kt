package com.francescooddo.buddygrammar.core

data class BuddySettings(
    val modelId: String = AppConfig.DEFAULT_MODEL,
    val usesAutomaticModelUpdates: Boolean = true,
    val correctionInstruction: String = AppConfig.DEFAULT_CORRECTION_INSTRUCTION.trimIndent(),
    val autoCorrectDictation: Boolean = true,
    val automaticallyCorrectWords: Boolean = true,
    val correctionUndoDurationSeconds: Int = 3,
    val hasAcceptedCloudProcessing: Boolean = false,
    val hasCompletedOnboarding: Boolean = false,
) {
    val activeModelId: String
        get() = if (usesAutomaticModelUpdates) AppConfig.DEFAULT_MODEL else modelId

    fun normalized(): BuddySettings = copy(
        modelId = if (usesAutomaticModelUpdates) AppConfig.DEFAULT_MODEL else modelId.trim(),
        correctionInstruction = correctionInstruction.trim(),
        correctionUndoDurationSeconds = correctionUndoDurationSeconds.coerceIn(1, 10),
    )
}

data class PendingTranscript(
    val text: String,
    val createdAtMillis: Long,
    val languageCode: String? = null,
)

data class SavedDictation(
    val rawTranscript: String,
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

internal fun restoreSavedDictation(
    rawTranscript: String?,
    text: String?,
    createdAtMillis: Long,
    languageCode: String?,
): SavedDictation? {
    val normalizedText = text?.trim().orEmpty()
    if (normalizedText.isEmpty() || createdAtMillis <= 0L) return null
    return SavedDictation(
        rawTranscript = rawTranscript?.trim()?.takeIf(String::isNotEmpty) ?: normalizedText,
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
