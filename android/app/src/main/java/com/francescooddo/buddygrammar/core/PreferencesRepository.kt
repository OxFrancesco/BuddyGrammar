package com.francescooddo.buddygrammar.core

import android.content.Context
import com.francescooddo.buddygrammar.core.adaptive.TypingProfileCodec
import com.francescooddo.buddygrammar.core.adaptive.TypingProfileSnapshot
import java.util.UUID

class PreferencesRepository(context: Context) {
    private val appContext = context.applicationContext
    private val preferences = appContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    fun loadSettings(): BuddySettings {
        val storedModel = preferences.getString(KEY_MODEL_ID, AppConfig.DEFAULT_MODEL)
            ?: AppConfig.DEFAULT_MODEL
        val usesAutomaticModelUpdates = if (preferences.contains(KEY_AUTOMATIC_MODEL_UPDATES)) {
            preferences.getBoolean(KEY_AUTOMATIC_MODEL_UPDATES, true)
        } else {
            storedModel in AppConfig.MANAGED_MODEL_IDS
        }
        val storedInstruction = preferences.getString(
            KEY_INSTRUCTION,
            AppConfig.DEFAULT_CORRECTION_INSTRUCTION.trimIndent(),
        ) ?: AppConfig.DEFAULT_CORRECTION_INSTRUCTION.trimIndent()
        val instruction = if (
            storedInstruction.trim() == AppConfig.LEGACY_CORRECTION_INSTRUCTION.trimIndent().trim()
        ) {
            AppConfig.DEFAULT_CORRECTION_INSTRUCTION.trimIndent()
        } else {
            storedInstruction
        }
        return BuddySettings(
            modelId = if (usesAutomaticModelUpdates) AppConfig.DEFAULT_MODEL else storedModel,
            usesAutomaticModelUpdates = usesAutomaticModelUpdates,
            correctionInstruction = instruction,
            autoCorrectDictation = preferences.getBoolean(KEY_AUTO_CORRECT, true),
            automaticallyCorrectWords = preferences.getBoolean(KEY_AUTOMATIC_WORD_CORRECTION, true),
            correctionUndoDurationSeconds = preferences.getInt(KEY_CORRECTION_UNDO_DURATION, 3)
                .coerceIn(1, 10),
            adaptiveTypingEnabled = preferences.getBoolean(KEY_ADAPTIVE_TYPING, true),
            personalizedPracticeEnabled = preferences.getBoolean(
                KEY_PERSONALIZED_PRACTICE,
                true,
            ),
            hasAcceptedCloudProcessing = preferences.getBoolean(KEY_CLOUD_CONSENT, false),
            hasCompletedOnboarding = preferences.getBoolean(KEY_ONBOARDING_COMPLETE, false),
        )
    }

    fun saveSettings(settings: BuddySettings) {
        val normalized = settings.normalized()
        preferences.edit()
            .putString(KEY_MODEL_ID, normalized.modelId)
            .putBoolean(KEY_AUTOMATIC_MODEL_UPDATES, normalized.usesAutomaticModelUpdates)
            .putString(KEY_INSTRUCTION, normalized.correctionInstruction)
            .putBoolean(KEY_AUTO_CORRECT, settings.autoCorrectDictation)
            .putBoolean(KEY_AUTOMATIC_WORD_CORRECTION, settings.automaticallyCorrectWords)
            .putInt(KEY_CORRECTION_UNDO_DURATION, normalized.correctionUndoDurationSeconds)
            .putBoolean(KEY_ADAPTIVE_TYPING, settings.adaptiveTypingEnabled)
            .putBoolean(KEY_PERSONALIZED_PRACTICE, settings.personalizedPracticeEnabled)
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

    fun loadTypingProfile(): TypingProfileSnapshot = TypingProfileCodec.decode(
        preferences.getString(KEY_TYPING_PROFILE, null),
    )

    fun saveTypingProfile(profile: TypingProfileSnapshot) {
        preferences.edit()
            .putString(KEY_TYPING_PROFILE, TypingProfileCodec.encode(profile))
            .apply()
    }

    fun clearTypingProfile() {
        preferences.edit().remove(KEY_TYPING_PROFILE).apply()
    }

    fun clearPersonalLanguageModel() {
        appContext.getSharedPreferences(PERSONAL_MODEL_PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .remove(PERSONAL_MODEL_KEY)
            .apply()
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

    fun saveDictation(
        rawTranscript: String,
        text: String,
        nowMillis: Long = System.currentTimeMillis(),
        languageCode: String? = null,
    ) {
        val editor = preferences.edit()
            .putString(KEY_SAVED_RAW_TRANSCRIPT, rawTranscript)
            .putString(KEY_SAVED_TEXT, text)
            .putLong(KEY_SAVED_DATE, nowMillis)
        val normalizedLanguage = languageCode?.trim()?.takeIf(String::isNotEmpty)
        if (normalizedLanguage == null) {
            editor.remove(KEY_SAVED_LANGUAGE)
        } else {
            editor.putString(KEY_SAVED_LANGUAGE, normalizedLanguage)
        }
        editor.apply()
    }

    fun loadSavedDictation(): SavedDictation? = restoreSavedDictation(
        rawTranscript = preferences.getString(KEY_SAVED_RAW_TRANSCRIPT, null),
        text = preferences.getString(KEY_SAVED_TEXT, null),
        createdAtMillis = preferences.getLong(KEY_SAVED_DATE, 0L),
        languageCode = preferences.getString(KEY_SAVED_LANGUAGE, null),
    )

    fun clearSavedDictation() {
        preferences.edit()
            .remove(KEY_SAVED_RAW_TRANSCRIPT)
            .remove(KEY_SAVED_TEXT)
            .remove(KEY_SAVED_DATE)
            .remove(KEY_SAVED_LANGUAGE)
            .apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "buddygrammar_shared"
        const val KEY_MODEL_ID = "settings.modelId"
        const val KEY_AUTOMATIC_MODEL_UPDATES = "settings.automaticModelUpdates"
        const val KEY_INSTRUCTION = "settings.instruction"
        const val KEY_AUTO_CORRECT = "settings.autoCorrectDictation"
        const val KEY_AUTOMATIC_WORD_CORRECTION = "settings.automaticallyCorrectWords"
        const val KEY_CORRECTION_UNDO_DURATION = "settings.correctionUndoDurationSeconds"
        const val KEY_ADAPTIVE_TYPING = "settings.adaptiveTypingEnabled"
        const val KEY_PERSONALIZED_PRACTICE = "settings.personalizedPracticeEnabled"
        const val KEY_CLOUD_CONSENT = "settings.cloudConsent"
        const val KEY_ONBOARDING_COMPLETE = "settings.onboardingComplete"
        const val KEY_INSTALLATION_ID = "installation.identifier"
        const val KEY_TYPING_PROFILE = "adaptive.typing.v1"
        const val KEY_TRANSCRIPT_TEXT = "transcript.text"
        const val KEY_TRANSCRIPT_DATE = "transcript.createdAt"
        const val KEY_TRANSCRIPT_LANGUAGE = "transcript.languageCode"
        const val KEY_SAVED_RAW_TRANSCRIPT = "dictation.rawTranscript"
        const val KEY_SAVED_TEXT = "dictation.text"
        const val KEY_SAVED_DATE = "dictation.createdAt"
        const val KEY_SAVED_LANGUAGE = "dictation.languageCode"
        const val PERSONAL_MODEL_PREFERENCES = "personal_language_model"
        const val PERSONAL_MODEL_KEY = "model"
    }
}
