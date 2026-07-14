package com.francescooddo.buddygrammar.ui

import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.francescooddo.buddygrammar.core.AudioRecorder
import com.francescooddo.buddygrammar.core.BuddyGrammarApi
import com.francescooddo.buddygrammar.core.BuddySettings
import com.francescooddo.buddygrammar.core.PendingTranscript
import com.francescooddo.buddygrammar.core.PreferencesRepository
import com.francescooddo.buddygrammar.ime.BuddyGrammarImeService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

enum class AppScreen {
    HOME,
    DICTATION,
    SETTINGS,
    KEYBOARD_LAB,
    PRIVACY,
}

data class AppNotice(val message: String, val isError: Boolean = false)

class BuddyGrammarAppState(context: Context) {
    private val appContext = context.applicationContext
    private val preferences = PreferencesRepository(appContext)
    private val api = BuddyGrammarApi()
    private val recorder = AudioRecorder(appContext)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val initialPendingTranscript = preferences.loadPendingTranscript()

    var settings by mutableStateOf(preferences.loadSettings())
        private set
    var screen by mutableStateOf(AppScreen.HOME)
        private set
    var onboardingPage by mutableIntStateOf(0)
        private set
    var pendingTranscript by mutableStateOf(initialPendingTranscript)
        private set
    var transcript by mutableStateOf(initialPendingTranscript?.text.orEmpty())
        private set
    var detectedLanguage by mutableStateOf(initialPendingTranscript?.languageCode)
        private set
    var isRecording by mutableStateOf(false)
        private set
    var isProcessing by mutableStateOf(false)
        private set
    var notice by mutableStateOf<AppNotice?>(null)
        private set
    var keyboardEnabled by mutableStateOf(false)
        private set
    var keyboardSelected by mutableStateOf(false)
        private set

    val needsOnboarding: Boolean
        get() = !settings.hasCompletedOnboarding

    fun updateOnboardingPage(page: Int) {
        onboardingPage = page.coerceIn(0, 2)
    }

    fun completeOnboarding(cloudConsent: Boolean) {
        settings = settings.copy(
            hasAcceptedCloudProcessing = cloudConsent,
            hasCompletedOnboarding = true,
        )
        preferences.saveSettings(settings)
        showNotice("BuddyGrammar is ready. Enable its keyboard to use ★ in other apps.")
    }

    fun navigate(destination: AppScreen) {
        screen = destination
        notice = null
    }

    fun saveSettings(updated: BuddySettings) {
        settings = updated.copy(hasCompletedOnboarding = true)
        preferences.saveSettings(settings)
        showNotice("Settings saved.")
    }

    fun updateTranscript(value: String) {
        transcript = value
    }

    fun saveTranscript() {
        val value = transcript.trim()
        if (value.isEmpty()) {
            showError("There is no transcript to save.")
            return
        }
        transcript = value
        preferences.savePendingTranscript(value, languageCode = detectedLanguage)
        pendingTranscript = PendingTranscript(value, System.currentTimeMillis(), detectedLanguage)
        showNotice("Saved for the keyboard microphone button.")
    }

    fun clearTranscript() {
        transcript = ""
        pendingTranscript = null
        detectedLanguage = null
        preferences.clearPendingTranscript()
        showNotice("Saved dictation cleared.")
    }

    fun startRecording() {
        if (!settings.hasAcceptedCloudProcessing) {
            showError("Allow cloud processing in Settings before recording.")
            return
        }
        runCatching { recorder.start() }
            .onSuccess {
                isRecording = true
                showNotice("Listening… tap again when you are done.")
            }
            .onFailure { showError(it.message ?: "The microphone could not start.") }
    }

    fun stopAndTranscribe() {
        if (!isRecording || isProcessing) return
        val recording = runCatching { recorder.stop() }.getOrElse {
            isRecording = false
            showError(it.message ?: "The recording could not be finished.")
            return
        }
        isRecording = false
        isProcessing = true
        showNotice("Transcribing securely with ElevenLabs…")

        scope.launch {
            try {
                val audio = withContext(Dispatchers.IO) { recording.readBytes() }
                val result = api.transcribe(
                    audio,
                    preferences.installationId(),
                    primaryDeviceLanguage(),
                )
                var correctionWarning: String? = null
                val finalText = if (settings.autoCorrectDictation) {
                    showNotice("Polishing the transcript…")
                    runCatching {
                        api.correct(
                            text = result.text,
                            clientId = preferences.installationId(),
                            modelId = settings.modelId,
                            instruction = settings.correctionInstruction,
                        )
                    }.getOrElse {
                        correctionWarning = it.message ?: "Correction was unavailable."
                        result.text
                    }
                } else {
                    result.text
                }
                transcript = finalText
                detectedLanguage = result.languageCode
                preferences.savePendingTranscript(
                    finalText,
                    languageCode = result.languageCode,
                )
                pendingTranscript = PendingTranscript(
                    finalText,
                    System.currentTimeMillis(),
                    result.languageCode,
                )
                showNotice(
                    correctionWarning?.let { "Transcript saved without correction: $it" }
                        ?: "Transcript saved and ready for the keyboard.",
                )
            } catch (error: Throwable) {
                showError(error.message ?: "The recording could not be processed.")
            } finally {
                recording.delete()
                isProcessing = false
            }
        }
    }

    fun cancelRecording() {
        if (!isRecording) return
        recorder.cancel()
        isRecording = false
        showNotice("Recording discarded.")
    }

    fun refresh() {
        settings = preferences.loadSettings()
        pendingTranscript = preferences.loadPendingTranscript()
        if (transcript.isEmpty()) {
            transcript = pendingTranscript?.text.orEmpty()
            detectedLanguage = pendingTranscript?.languageCode
        }
        refreshKeyboardStatus()
    }

    fun refreshKeyboardStatus() {
        val inputManager = appContext.getSystemService(InputMethodManager::class.java)
        keyboardEnabled = inputManager.enabledInputMethodList.any {
            it.serviceInfo.packageName == appContext.packageName &&
                it.serviceInfo.name == BuddyGrammarImeService::class.java.name
        }
        val component = ComponentName(appContext, BuddyGrammarImeService::class.java)
        val selected = Settings.Secure.getString(
            appContext.contentResolver,
            Settings.Secure.DEFAULT_INPUT_METHOD,
        )
        keyboardSelected = selected == component.flattenToShortString() ||
            selected == component.flattenToString()
    }

    fun showError(message: String) {
        notice = AppNotice(message, isError = true)
    }

    private fun showNotice(message: String) {
        notice = AppNotice(message)
    }

    private fun primaryDeviceLanguage(): String {
        val configured = appContext.resources.configuration.locales
            .takeIf { !it.isEmpty }
            ?.get(0)
            ?.language
            ?.takeIf { it.isNotBlank() }
        return configured ?: Locale.getDefault().language
    }

    fun close() {
        recorder.cancel()
        scope.cancel()
    }
}
