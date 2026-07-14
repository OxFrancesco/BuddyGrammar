package com.francescooddo.buddygrammar.core

import android.content.Context
import java.util.UUID

class PreferencesRepository(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    fun loadSettings(): BuddySettings = BuddySettings(
        modelId = preferences.getString(KEY_MODEL_ID, AppConfig.DEFAULT_MODEL)
            ?: AppConfig.DEFAULT_MODEL,
        correctionInstruction = preferences.getString(
            KEY_INSTRUCTION,
            AppConfig.DEFAULT_CORRECTION_INSTRUCTION.trimIndent(),
        ) ?: AppConfig.DEFAULT_CORRECTION_INSTRUCTION.trimIndent(),
        autoCorrectDictation = preferences.getBoolean(KEY_AUTO_CORRECT, true),
        automaticallyCorrectWords = preferences.getBoolean(KEY_AUTOMATIC_WORD_CORRECTION, true),
        hasAcceptedCloudProcessing = preferences.getBoolean(KEY_CLOUD_CONSENT, false),
        hasCompletedOnboarding = preferences.getBoolean(KEY_ONBOARDING_COMPLETE, false),
    )

    fun saveSettings(settings: BuddySettings) {
        preferences.edit()
            .putString(KEY_MODEL_ID, settings.modelId)
            .putString(KEY_INSTRUCTION, settings.correctionInstruction)
            .putBoolean(KEY_AUTO_CORRECT, settings.autoCorrectDictation)
            .putBoolean(KEY_AUTOMATIC_WORD_CORRECTION, settings.automaticallyCorrectWords)
            .putBoolean(KEY_CLOUD_CONSENT, settings.hasAcceptedCloudProcessing)
            .putBoolean(KEY_ONBOARDING_COMPLETE, settings.hasCompletedOnboarding)
            .apply()
    }

    fun installationId(): UUID {
        val stored = preferences.getString(KEY_INSTALLATION_ID, null)
        runCatching { UUID.fromString(stored) }.getOrNull()?.let { return it }

        return UUID.randomUUID().also { identifier ->
            preferences.edit().putString(KEY_INSTALLATION_ID, identifier.toString()).apply()
        }
    }

    fun savePendingTranscript(
        text: String,
        nowMillis: Long = System.currentTimeMillis(),
        languageCode: String? = null,
    ) {
        val editor = preferences.edit()
            .putString(KEY_TRANSCRIPT_TEXT, text)
            .putLong(KEY_TRANSCRIPT_DATE, nowMillis)
        val normalizedLanguage = languageCode?.trim()?.takeIf(String::isNotEmpty)
        if (normalizedLanguage == null) {
            editor.remove(KEY_TRANSCRIPT_LANGUAGE)
        } else {
            editor.putString(KEY_TRANSCRIPT_LANGUAGE, normalizedLanguage)
        }
        editor.apply()
    }

    fun loadPendingTranscript(nowMillis: Long = System.currentTimeMillis()): PendingTranscript? {
        val transcript = restorePendingTranscript(
            text = preferences.getString(KEY_TRANSCRIPT_TEXT, null),
            createdAtMillis = preferences.getLong(KEY_TRANSCRIPT_DATE, 0L),
            languageCode = preferences.getString(KEY_TRANSCRIPT_LANGUAGE, null),
        ) ?: return null
        if (nowMillis - transcript.createdAtMillis > AppConfig.PENDING_TRANSCRIPT_LIFETIME_MS) {
            clearPendingTranscript()
            return null
        }
        return transcript
    }

    fun clearPendingTranscript() {
        preferences.edit()
            .remove(KEY_TRANSCRIPT_TEXT)
            .remove(KEY_TRANSCRIPT_DATE)
            .remove(KEY_TRANSCRIPT_LANGUAGE)
            .apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "buddygrammar_shared"
        const val KEY_MODEL_ID = "settings.modelId"
        const val KEY_INSTRUCTION = "settings.instruction"
        const val KEY_AUTO_CORRECT = "settings.autoCorrectDictation"
        const val KEY_AUTOMATIC_WORD_CORRECTION = "settings.automaticallyCorrectWords"
        const val KEY_CLOUD_CONSENT = "settings.cloudConsent"
        const val KEY_ONBOARDING_COMPLETE = "settings.onboardingComplete"
        const val KEY_INSTALLATION_ID = "installation.identifier"
        const val KEY_TRANSCRIPT_TEXT = "transcript.text"
        const val KEY_TRANSCRIPT_DATE = "transcript.createdAt"
        const val KEY_TRANSCRIPT_LANGUAGE = "transcript.languageCode"
    }
}
