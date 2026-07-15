package com.francescooddo.buddygrammar.ui

import android.content.ComponentName
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.provider.Settings
import android.util.Log
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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
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
    private val clipboard = appContext.getSystemService(ClipboardManager::class.java)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val initialPendingTranscript = preferences.loadPendingTranscript()
    private val initialSavedDictation = preferences.loadSavedDictation()

    var settings by mutableStateOf(preferences.loadSettings())
        private set
    var screen by mutableStateOf(AppScreen.HOME)
        private set
    var onboardingPage by mutableIntStateOf(0)
        private set
    var pendingTranscript by mutableStateOf(initialPendingTranscript)
        private set
    var transcript by mutableStateOf(
        initialPendingTranscript?.text ?: initialSavedDictation?.text.orEmpty(),
    )
        private set
    var detectedLanguage by mutableStateOf(
        initialPendingTranscript?.languageCode ?: initialSavedDictation?.languageCode,
    )
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
        preferences.saveDictation(
            rawTranscript = value,
            text = value,
            languageCode = detectedLanguage,
        )
        pendingTranscript = PendingTranscript(value, System.currentTimeMillis(), detectedLanguage)
        copyToClipboard(value)
        showNotice("Saved locally, copied, and ready for the keyboard.")
    }

    fun clearTranscript() {
        transcript = ""
        pendingTranscript = null
        detectedLanguage = null
        preferences.clearPendingTranscript()
        preferences.clearSavedDictation()
        showNotice("Saved dictation cleared.")
    }

    fun copyTranscript() {
        val value = transcript.trim()
        if (value.isEmpty()) return
        copyToClipboard(value)
        showNotice("Transcript copied to the clipboard.")
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
                val result = retryTranscriptionOnce(
                    onFailure = { error, attempt ->
                        Log.w(
                            DICTATION_LOG_TAG,
                            "Transcription attempt $attempt failed",
                            error,
                        )
                    },
                ) {
                    api.transcribe(
                        audio,
                        preferences.installationId(),
                        primaryDeviceLanguage(),
                    )
                }
                var correctionWarning: String? = null
                val finalText = if (settings.autoCorrectDictation) {
                    showNotice("Polishing the transcript…")
                    runCatching {
                        api.correct(
                            text = result.text,
                            clientId = preferences.installationId(),
                            modelId = settings.activeModelId,
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
                preferences.saveDictation(
                    rawTranscript = result.text,
                    text = finalText,
                    languageCode = result.languageCode,
                )
                pendingTranscript = PendingTranscript(
                    finalText,
                    System.currentTimeMillis(),
                    result.languageCode,
                )
                copyToClipboard(finalText)
                showNotice(
                    correctionWarning?.let { "Transcript saved and copied without correction: $it" }
                        ?: "Transcript saved locally, copied, and ready for the keyboard.",
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
            val savedDictation = preferences.loadSavedDictation()
            transcript = pendingTranscript?.text ?: savedDictation?.text.orEmpty()
            detectedLanguage = pendingTranscript?.languageCode ?: savedDictation?.languageCode
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

    private fun copyToClipboard(text: String) {
        clipboard.setPrimaryClip(ClipData.newPlainText("BuddyGrammar transcript", text))
    }

    fun close() {
        recorder.cancel()
        scope.cancel()
    }

    private companion object {
        const val DICTATION_LOG_TAG = "BuddyGrammarDictation"
    }
}

internal suspend fun <T> retryTranscriptionOnce(
    delayMillis: Long = 750L,
    onFailure: (Throwable, Int) -> Unit = { _, _ -> },
    operation: suspend () -> T,
): T {
    var lastError: Throwable? = null
    repeat(2) { index ->
        try {
            return operation()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            lastError = error
            onFailure(error, index + 1)
            if (index == 0) delay(delayMillis)
        }
    }
    throw IOException(
        "We couldn’t transcribe this recording after two attempts. Please try again later.",
        lastError,
    )
}
