package com.francescooddo.buddygrammar.ime

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import com.francescooddo.buddygrammar.core.LanguageSupport
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognition
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognitionModel
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognitionModelIdentifier
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognizer
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognizerOptions
import com.google.mlkit.vision.digitalink.recognition.Ink
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Captures handwriting strokes and recognizes them with ML Kit digital ink.
 * Degrades gracefully when Play services or the language model is unavailable.
 */
class HandwritingController(
    private val scope: CoroutineScope,
    private val languageTagProvider: () -> String = { LanguageSupport.DEFAULT_LANGUAGE_TAG },
) {
    val finishedStrokes = mutableStateListOf<List<Offset>>()
    var activeStroke by mutableStateOf<List<Offset>>(emptyList())
        private set
    var candidates by mutableStateOf<List<String>>(emptyList())
        private set
    var statusMessage by mutableStateOf<String?>(null)
        private set
    var isModelDownloading by mutableStateOf(false)
        private set

    private var inkBuilder = Ink.builder()
    private var strokeBuilder: Ink.Stroke.Builder? = null
    private var recognitionJob: Job? = null
    private var modelReady = false
    private var configuredLanguageTag: String? = null
    private var configurationGeneration = 0
    private var model: DigitalInkRecognitionModel? = null
    private var recognizer: DigitalInkRecognizer? = null

    fun startStroke(position: Offset, timeMillis: Long) {
        recognitionJob?.cancel()
        strokeBuilder = Ink.Stroke.builder().apply {
            addPoint(Ink.Point.create(position.x, position.y, timeMillis))
        }
        activeStroke = listOf(position)
    }

    fun addPoint(position: Offset, timeMillis: Long) {
        strokeBuilder?.addPoint(Ink.Point.create(position.x, position.y, timeMillis))
        activeStroke = activeStroke + position
    }

    fun endStroke() {
        strokeBuilder?.let { builder ->
            inkBuilder.addStroke(builder.build())
            if (activeStroke.isNotEmpty()) finishedStrokes.add(activeStroke)
        }
        strokeBuilder = null
        activeStroke = emptyList()
        scheduleRecognition()
    }

    fun clear() {
        recognitionJob?.cancel()
        recognitionJob = null
        inkBuilder = Ink.builder()
        strokeBuilder = null
        finishedStrokes.clear()
        activeStroke = emptyList()
        candidates = emptyList()
    }

    fun destroy() {
        clear()
        runCatching { recognizer?.close() }
        recognizer = null
        model = null
        configuredLanguageTag = null
        configurationGeneration += 1
        modelReady = false
        isModelDownloading = false
    }

    /** Checks model availability and starts the download when needed. */
    fun prepareModel() {
        val generation = configureForCurrentLanguage()
        val inkModel = model
        if (inkModel == null || recognizer == null) {
            statusMessage = "Handwriting recognition is unavailable for this language."
            return
        }
        if (modelReady || isModelDownloading) return
        val manager = RemoteModelManager.getInstance()
        manager.isModelDownloaded(inkModel)
            .addOnSuccessListener { downloaded ->
                if (generation != configurationGeneration) return@addOnSuccessListener
                if (downloaded) {
                    modelReady = true
                    statusMessage = null
                    if (hasInk()) recognizeNow()
                } else {
                    downloadModel(manager, inkModel, generation)
                }
            }
            .addOnFailureListener { error ->
                if (generation != configurationGeneration) return@addOnFailureListener
                statusMessage = error.message ?: "The handwriting model could not be checked."
            }
    }

    private fun downloadModel(
        manager: RemoteModelManager,
        inkModel: DigitalInkRecognitionModel,
        generation: Int,
    ) {
        isModelDownloading = true
        statusMessage = "Downloading handwriting model…"
        manager.download(inkModel, DownloadConditions.Builder().build())
            .addOnSuccessListener {
                if (generation != configurationGeneration) return@addOnSuccessListener
                isModelDownloading = false
                modelReady = true
                statusMessage = null
                if (hasInk()) recognizeNow()
            }
            .addOnFailureListener { error ->
                if (generation != configurationGeneration) return@addOnFailureListener
                isModelDownloading = false
                statusMessage = error.message ?: "The handwriting model could not be downloaded."
            }
    }

    private fun scheduleRecognition() {
        recognitionJob?.cancel()
        recognitionJob = scope.launch {
            delay(RECOGNITION_DEBOUNCE_MS)
            recognizeNow()
        }
    }

    private fun recognizeNow() {
        val generation = configureForCurrentLanguage()
        val activeRecognizer = recognizer
        if (activeRecognizer == null) {
            statusMessage = "Handwriting recognition is unavailable for this language."
            return
        }
        if (!modelReady) {
            prepareModel()
            return
        }
        if (!hasInk()) return
        activeRecognizer.recognize(inkBuilder.build())
            .addOnSuccessListener { result ->
                if (
                    generation != configurationGeneration ||
                    activeRecognizer !== recognizer
                ) {
                    return@addOnSuccessListener
                }
                candidates = result.candidates
                    .map { it.text.trim() }
                    .filter { it.isNotEmpty() }
                    .distinct()
                    .take(3)
            }
            .addOnFailureListener { error ->
                if (
                    generation != configurationGeneration ||
                    activeRecognizer !== recognizer
                ) {
                    return@addOnFailureListener
                }
                statusMessage = error.message ?: "Handwriting could not be recognized."
            }
    }

    private fun configureForCurrentLanguage(): Int {
        val requested = languageTagProvider().trim()
            .ifEmpty { LanguageSupport.DEFAULT_LANGUAGE_TAG }
        if (requested == configuredLanguageTag && model != null && recognizer != null) {
            return configurationGeneration
        }

        configurationGeneration += 1
        configuredLanguageTag = requested
        runCatching { recognizer?.close() }
        recognizer = null
        model = null
        modelReady = false
        isModelDownloading = false
        candidates = emptyList()
        statusMessage = null

        val primaryLanguage = LanguageSupport.scope(requested)
        val identifier = sequenceOf(requested, primaryLanguage)
            .distinct()
            .mapNotNull { languageTag ->
                runCatching {
                    DigitalInkRecognitionModelIdentifier.fromLanguageTag(languageTag)
                }.getOrNull()
            }
            .firstOrNull()
        model = identifier?.let { modelIdentifier ->
            runCatching {
                DigitalInkRecognitionModel.builder(modelIdentifier).build()
            }.getOrNull()
        }
        recognizer = model?.let { inkModel ->
            runCatching {
                DigitalInkRecognition.getClient(
                    DigitalInkRecognizerOptions.builder(inkModel).build(),
                )
            }.getOrNull()
        }
        return configurationGeneration
    }

    private fun hasInk(): Boolean = finishedStrokes.isNotEmpty()

    private companion object {
        const val RECOGNITION_DEBOUNCE_MS = 800L
    }
}
