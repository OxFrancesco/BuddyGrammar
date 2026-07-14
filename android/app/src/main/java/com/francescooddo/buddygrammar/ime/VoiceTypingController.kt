package com.francescooddo.buddygrammar.ime

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.Locale

/**
 * Wraps [SpeechRecognizer] for in-keyboard dictation on the VOICE layer.
 */
class VoiceTypingController(
    private val context: Context,
    private val onFinalText: (String) -> Unit,
    private val languageTagProvider: () -> String = { Locale.getDefault().toLanguageTag() },
) {
    var isListening by mutableStateOf(false)
        private set
    var partialText by mutableStateOf("")
        private set
    var rmsLevel by mutableFloatStateOf(0f)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set

    private var recognizer: SpeechRecognizer? = null

    val isRecognitionAvailable: Boolean
        get() = SpeechRecognizer.isRecognitionAvailable(context)

    fun toggleListening() {
        if (isListening) stopListening() else startListening()
    }

    fun startListening() {
        if (isListening) return
        if (!isRecognitionAvailable) {
            errorMessage = "Speech recognition is not available on this device."
            return
        }
        errorMessage = null
        partialText = ""
        val speechRecognizer = recognizer ?: SpeechRecognizer.createSpeechRecognizer(context)
            .also { recognizer = it }
        speechRecognizer.setRecognitionListener(listener)
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
            languageTagProvider().trim().takeIf(String::isNotEmpty)?.let { languageTag ->
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
            }
        }
        runCatching { speechRecognizer.startListening(intent) }
            .onSuccess { isListening = true }
            .onFailure { errorMessage = it.message ?: "Dictation could not start." }
    }

    fun stopListening() {
        if (!isListening) return
        runCatching { recognizer?.stopListening() }
        isListening = false
    }

    /** Cancels recognition and releases the recognizer. */
    fun destroy() {
        runCatching { recognizer?.cancel() }
        runCatching { recognizer?.destroy() }
        recognizer = null
        isListening = false
        partialText = ""
        rmsLevel = 0f
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            errorMessage = null
        }

        override fun onBeginningOfSpeech() = Unit

        override fun onRmsChanged(rmsdB: Float) {
            rmsLevel = ((rmsdB + 2f) / 12f).coerceIn(0f, 1f)
        }

        override fun onBufferReceived(buffer: ByteArray?) = Unit

        override fun onEndOfSpeech() {
            rmsLevel = 0f
        }

        override fun onError(error: Int) {
            isListening = false
            rmsLevel = 0f
            errorMessage = when (error) {
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
                -> "No speech was heard. Tap the microphone to try again."
                SpeechRecognizer.ERROR_AUDIO -> "The microphone could not record audio."
                SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                -> "Dictation needs a network connection."
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                    "Microphone permission is required for dictation."
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "The recognizer is busy. Try again shortly."
                else -> "Dictation stopped (error $error)."
            }
        }

        override fun onResults(results: Bundle?) {
            isListening = false
            rmsLevel = 0f
            partialText = ""
            val best = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?.trim()
                .orEmpty()
            if (best.isNotEmpty()) onFinalText(best)
        }

        override fun onPartialResults(partialResults: Bundle?) {
            partialText = partialResults
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                .orEmpty()
        }

        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }
}
