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
internal class VoiceTypingController(
    private val context: Context,
    private val onFinalText: (VoiceRequestToken, String) -> Boolean,
    private val onRequestFinished: (VoiceRequestToken) -> Boolean,
    private val isRequestOwner: (VoiceRequestToken) -> Boolean,
    private val onCancelled: () -> Unit,
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

    fun startListening(request: VoiceRequestToken) {
        if (isListening) return
        if (!isRequestOwner(request)) return
        if (!isRecognitionAvailable) {
            if (onRequestFinished(request)) {
                errorMessage = "Speech recognition is not available on this device."
            }
            return
        }
        errorMessage = null
        partialText = ""
        releaseRecognizer(cancel = true)
        val speechRecognizer = runCatching { SpeechRecognizer.createSpeechRecognizer(context) }
            .getOrElse { error ->
                if (onRequestFinished(request)) {
                    errorMessage = error.message ?: "Dictation could not start."
                }
                return
        }
        recognizer = speechRecognizer
        runCatching {
            speechRecognizer.setRecognitionListener(listenerFor(request, speechRecognizer))
        }.onFailure { error ->
            if (onRequestFinished(request)) {
                errorMessage = error.message ?: "Dictation could not start."
            }
            releaseRecognizerIfCurrent(speechRecognizer, cancel = true)
            return
        }
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
            .onFailure { error ->
                if (onRequestFinished(request)) {
                    errorMessage = error.message ?: "Dictation could not start."
                }
                releaseRecognizerIfCurrent(speechRecognizer, cancel = true)
            }
    }

    fun stopListening() {
        if (!isListening) return
        runCatching { recognizer?.stopListening() }
        isListening = false
    }

    /** Invalidates the active owner, then cancels and releases its recognizer. */
    fun cancel() {
        onCancelled()
        releaseRecognizer(cancel = true)
        isListening = false
        partialText = ""
        rmsLevel = 0f
    }

    private fun listenerFor(
        request: VoiceRequestToken,
        source: SpeechRecognizer,
    ): RecognitionListener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            if (!isRequestOwner(request)) return
            errorMessage = null
        }

        override fun onBeginningOfSpeech() = Unit

        override fun onRmsChanged(rmsdB: Float) {
            if (!isRequestOwner(request)) return
            rmsLevel = ((rmsdB + 2f) / 12f).coerceIn(0f, 1f)
        }

        override fun onBufferReceived(buffer: ByteArray?) = Unit

        override fun onEndOfSpeech() {
            if (!isRequestOwner(request)) return
            rmsLevel = 0f
        }

        override fun onError(error: Int) {
            if (!onRequestFinished(request)) return
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
            releaseRecognizerIfCurrent(source, cancel = false)
        }

        override fun onResults(results: Bundle?) {
            val best = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?.trim()
                .orEmpty()
            val accepted = if (best.isEmpty()) {
                onRequestFinished(request)
            } else {
                onFinalText(request, best)
            }
            if (!accepted) return
            isListening = false
            rmsLevel = 0f
            partialText = ""
            releaseRecognizerIfCurrent(source, cancel = false)
        }

        override fun onPartialResults(partialResults: Bundle?) {
            if (!isRequestOwner(request)) return
            partialText = partialResults
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                .orEmpty()
        }

        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    private fun releaseRecognizer(cancel: Boolean) {
        val current = recognizer ?: return
        recognizer = null
        if (cancel) runCatching { current.cancel() }
        runCatching { current.destroy() }
    }

    private fun releaseRecognizerIfCurrent(source: SpeechRecognizer, cancel: Boolean) {
        if (recognizer !== source) return
        releaseRecognizer(cancel)
    }
}
