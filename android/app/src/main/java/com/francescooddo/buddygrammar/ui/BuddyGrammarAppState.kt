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
import com.francescooddo.buddygrammar.core.adaptive.ActivePracticeSession
import com.francescooddo.buddygrammar.core.adaptive.AdaptivePracticeStore
import com.francescooddo.buddygrammar.core.adaptive.PracticeAssistance
import com.francescooddo.buddygrammar.core.adaptive.PracticeAttempt
import com.francescooddo.buddygrammar.core.adaptive.PracticeCoach
import com.francescooddo.buddygrammar.core.adaptive.PracticeProfile
import com.francescooddo.buddygrammar.core.adaptive.PracticePrompt
import com.francescooddo.buddygrammar.core.adaptive.PracticeRequest
import com.francescooddo.buddygrammar.core.adaptive.PracticeResult
import com.francescooddo.buddygrammar.core.adaptive.PracticeTrack
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

data class PracticeProgressSummary(
    val completedAttempts: Int,
    val averageAccuracy: Double,
    val averageMastery: Double,
    val trackedSkills: Int,
    val nextReviewAtEpochMillis: Long?,
    val reviewIsDue: Boolean,
)

class BuddyGrammarAppState(context: Context) {
    private val appContext = context.applicationContext
    private val preferences = PreferencesRepository(appContext)
    private val initialSettings = preferences.loadSettings()
    private val practiceStore = AdaptivePracticeStore(appContext)
    private var practiceCoach = PracticeCoach(
        if (initialSettings.personalizedPracticeEnabled) practiceStore.load() else PracticeProfile(),
    )
    private val api = BuddyGrammarApi()
    private val recorder = AudioRecorder(appContext)
    private val clipboard = appContext.getSystemService(ClipboardManager::class.java)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val initialPendingTranscript = preferences.loadPendingTranscript()
    private val initialSavedDictation = preferences.loadSavedDictation()
    private var practiceEditorActive = false

    var settings by mutableStateOf(initialSettings)
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
    var practiceTrack by mutableStateOf(PracticeTrack.MIXED)
        private set
    var practicePrompt by mutableStateOf<PracticePrompt?>(null)
        private set
    var practiceResponse by mutableStateOf("")
        private set
    var practiceResult by mutableStateOf<PracticeResult?>(null)
        private set
    var practiceProfile by mutableStateOf(practiceCoach.snapshot())
        private set

    val needsOnboarding: Boolean
        get() = !settings.hasCompletedOnboarding

    val practiceSummary: PracticeProgressSummary
        get() {
            val skills = practiceProfile.skills.values
            val now = System.currentTimeMillis()
            val reviewDates = skills
                .flatMap { it.retentionSchedule }
                .map { it.dueAtEpochMillis }
            return PracticeProgressSummary(
                completedAttempts = practiceProfile.completedAttempts,
                averageAccuracy = practiceProfile.meanRawAccuracy,
                averageMastery = if (skills.isEmpty()) 0.0 else skills.map { it.mastery }.average(),
                trackedSkills = skills.size,
                nextReviewAtEpochMillis = reviewDates.filter { it > now }.minOrNull(),
                reviewIsDue = reviewDates.any { it <= now },
            )
        }

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
        if (screen == AppScreen.KEYBOARD_LAB && destination != AppScreen.KEYBOARD_LAB) {
            leavePracticeEditor()
        }
        screen = destination
        notice = null
        if (destination == AppScreen.KEYBOARD_LAB) ensurePracticePrompt()
    }

    fun saveSettings(updated: BuddySettings) {
        val personalizationChanged = settings.personalizedPracticeEnabled !=
            updated.personalizedPracticeEnabled
        settings = updated.copy(hasCompletedOnboarding = true)
        preferences.saveSettings(settings)
        if (personalizationChanged) {
            practiceCoach = PracticeCoach(
                if (settings.personalizedPracticeEnabled) practiceStore.load() else PracticeProfile(),
            )
            practiceProfile = practiceCoach.snapshot()
            practicePrompt = null
            practiceResponse = ""
            practiceResult = null
            practiceStore.clearActiveSession()
            if (screen == AppScreen.KEYBOARD_LAB) ensurePracticePrompt()
        }
        showNotice("Settings saved.")
    }

    fun selectPracticeTrack(track: PracticeTrack) {
        if (practiceTrack == track && practicePrompt != null && practiceResult == null) return
        practiceTrack = track
        practiceResponse = ""
        practiceResult = null
        choosePracticePrompt()
    }

    fun updatePracticeResponse(value: String) {
        practiceResponse = value.take(MAX_PRACTICE_RESPONSE_LENGTH)
    }

    fun setPracticeEditorActive(active: Boolean) {
        practiceEditorActive = active && screen == AppScreen.KEYBOARD_LAB && practiceResult == null
        if (practiceEditorActive) {
            practicePrompt?.let(::saveActivePracticeSession)
        } else {
            practiceStore.clearActiveSession()
        }
    }

    fun submitPracticeAttempt() {
        val prompt = practicePrompt ?: return
        if (practiceResponse.isBlank()) {
            showError("Type a response before submitting, or skip this prompt.")
            return
        }
        val result = practiceCoach.record(
            PracticeAttempt(
                prompt = prompt,
                rawText = practiceResponse,
                assistance = if (settings.adaptiveTypingEnabled && keyboardSelected) {
                    PracticeAssistance.ADAPTIVE_KEYBOARD
                } else {
                    PracticeAssistance.NONE
                },
            ),
            nowEpochMillis = System.currentTimeMillis(),
        )
        practiceResult = result
        practiceProfile = practiceCoach.snapshot()
        persistPracticeProfileIfAllowed()
        practiceEditorActive = false
        practiceStore.clearActiveSession()
        showNotice("Attempt scored locally. Your response was not saved.")
    }

    fun skipPracticePrompt() {
        practicePrompt?.let { prompt ->
            practiceCoach.record(
                PracticeAttempt(prompt = prompt, rawText = "", abandoned = true),
                nowEpochMillis = System.currentTimeMillis(),
            )
            practiceProfile = practiceCoach.snapshot()
            persistPracticeProfileIfAllowed()
        }
        practiceResponse = ""
        practiceResult = null
        practiceEditorActive = false
        practiceStore.clearActiveSession()
        choosePracticePrompt()
    }

    fun nextPracticePrompt() {
        practiceResponse = ""
        practiceResult = null
        choosePracticePrompt()
    }

    fun resetPracticeProgress() {
        clearPracticeProgress()
        showNotice("Adaptive practice progress reset.")
    }

    fun resetTypingCalibration() {
        preferences.clearTypingProfile()
        showNotice("Touch calibration reset.")
    }

    fun resetLearnedWords() {
        preferences.clearPersonalLanguageModel()
        showNotice("Learned words reset.")
    }

    fun resetAllLearning() {
        preferences.clearTypingProfile()
        preferences.clearPersonalLanguageModel()
        clearPracticeProgress()
        showNotice("All on-device learning reset.")
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
        val refreshedSettings = preferences.loadSettings()
        if (settings.personalizedPracticeEnabled != refreshedSettings.personalizedPracticeEnabled) {
            practiceCoach = PracticeCoach(
                if (refreshedSettings.personalizedPracticeEnabled) {
                    practiceStore.load()
                } else {
                    PracticeProfile()
                },
            )
            practiceProfile = practiceCoach.snapshot()
        }
        settings = refreshedSettings
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

    private fun ensurePracticePrompt() {
        if (practicePrompt == null || practiceResult != null) choosePracticePrompt()
        else saveActivePracticeSession(practicePrompt ?: return)
    }

    private fun choosePracticePrompt() {
        val now = System.currentTimeMillis()
        val prompt = practiceCoach.nextPrompt(
            PracticeRequest(track = practiceTrack),
            nowEpochMillis = now,
        )
        practicePrompt = prompt
        saveActivePracticeSession(prompt, now)
    }

    private fun saveActivePracticeSession(
        prompt: PracticePrompt,
        nowEpochMillis: Long = System.currentTimeMillis(),
    ) {
        if (screen != AppScreen.KEYBOARD_LAB || !practiceEditorActive) return
        practiceStore.saveActiveSession(
            ActivePracticeSession(
                promptId = prompt.id,
                expectedText = prompt.expectedText,
                startedAtEpochMillis = nowEpochMillis,
                expiresAtEpochMillis = nowEpochMillis + PRACTICE_SESSION_TTL_MILLIS,
            ),
        )
    }

    private fun persistPracticeProfileIfAllowed() {
        if (settings.personalizedPracticeEnabled) practiceStore.save(practiceProfile)
    }

    private fun clearPracticeProgress() {
        practiceStore.reset()
        practiceCoach = PracticeCoach()
        practiceProfile = practiceCoach.snapshot()
        practicePrompt = null
        practiceResponse = ""
        practiceResult = null
        practiceEditorActive = false
        if (screen == AppScreen.KEYBOARD_LAB) ensurePracticePrompt()
    }

    private fun leavePracticeEditor() {
        practiceEditorActive = false
        practiceStore.clearActiveSession()
        practiceResponse = ""
        practiceResult = null
        practicePrompt = null
    }

    fun close() {
        recorder.cancel()
        leavePracticeEditor()
        scope.cancel()
    }

    private companion object {
        const val DICTATION_LOG_TAG = "BuddyGrammarDictation"
        const val PRACTICE_SESSION_TTL_MILLIS = 30 * 60 * 1_000L
        const val MAX_PRACTICE_RESPONSE_LENGTH = 2_000
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
