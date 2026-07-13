package com.francescooddo.buddygrammar.core

data class BuddySettings(
    val modelId: String = AppConfig.DEFAULT_MODEL,
    val correctionInstruction: String = AppConfig.DEFAULT_CORRECTION_INSTRUCTION.trimIndent(),
    val autoCorrectDictation: Boolean = true,
    val hasAcceptedCloudProcessing: Boolean = false,
    val hasCompletedOnboarding: Boolean = false,
)

data class PendingTranscript(
    val text: String,
    val createdAtMillis: Long,
)

data class TranscriptResult(
    val text: String,
    val languageCode: String?,
    val languageProbability: Double?,
)
