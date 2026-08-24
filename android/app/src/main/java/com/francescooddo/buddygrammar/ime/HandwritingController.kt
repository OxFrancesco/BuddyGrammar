package com.francescooddo.buddygrammar.ime

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import androidx.compose.runtime.getValue
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
import java.io.ByteArrayOutputStream
import kotlin.math.min

/**
 * Captures handwriting strokes and recognizes them with ML Kit digital ink.
 * Degrades gracefully when Play services or the language model is unavailable.
 */
class HandwritingController(
    private val scope: CoroutineScope,
    private val languageTagProvider: () -> String = { LanguageSupport.DEFAULT_LANGUAGE_TAG },
    private val cloudFallback: suspend (ByteArray) -> String? = { null },
    private val cloudUnavailableMessage: () -> String? = { null },
    private val publicationAllowed: (requiresCloud: Boolean) -> Boolean = { true },
) {
    private val inputBuffer = HandwritingInputBuffer()
    private var inputRevision by mutableStateOf(0)
    private val requestOwnership = HandwritingRequestOwnership()

    val finishedStrokes: List<List<Offset>>
        get() {
            inputRevision
            return inputBuffer.finishedStrokes.map { stroke ->
                stroke.map { point -> Offset(point.x, point.y) }
            }
        }

    val activeStroke: List<Offset>
        get() {
            inputRevision
            return inputBuffer.activeStroke.map { point -> Offset(point.x, point.y) }
        }
    var candidates by mutableStateOf<List<String>>(emptyList())
        private set
    var statusMessage by mutableStateOf<String?>(null)
        private set
    var isModelDownloading by mutableStateOf(false)
        private set
    var isUsingCloud by mutableStateOf(false)
        private set

    private var recognitionJob: Job? = null
    private var modelReady = false
    private var configuredLanguageTag: String? = null
    private var configurationGeneration = 0
    private var model: DigitalInkRecognitionModel? = null
    private var recognizer: DigitalInkRecognizer? = null
    private var candidateStamp: HandwritingWorkStamp? = null
    private var panelActive = false

    fun activate(fieldEpoch: Long) {
        changeField(fieldEpoch)
        panelActive = true
        prepareModel()
    }

    fun deactivate() {
        panelActive = false
        configurationGeneration += 1
        clear()
    }

    fun changeField(fieldEpoch: Long) {
        if (requestOwnership.fieldEpoch == fieldEpoch) return
        requestOwnership.changeField(fieldEpoch)
        clear(resetOwnership = false)
    }

    /** Invalidates old-language work before the service exposes a new subtype. */
    fun languageChanged() {
        requestOwnership.inputChanged()
        clear(resetOwnership = false)
        configurationGeneration += 1
        configuredLanguageTag = null
        modelReady = false
        isModelDownloading = false
        runCatching { recognizer?.close() }
        recognizer = null
        model = null
        if (panelActive) prepareModel()
    }

    fun consumeCandidate(text: String, fieldEpoch: Long): String? {
        val stamp = candidateStamp ?: return null
        return text.takeIf {
            panelActive &&
                fieldEpoch == requestOwnership.fieldEpoch &&
                requestOwnership.isCurrent(stamp) &&
                text in candidates
        }
    }

    fun startStroke(position: Offset, timeMillis: Long) {
        recognitionJob?.cancel()
        inputBuffer.start(position.inputPoint(timeMillis))
        markInputChanged()
    }

    fun addPoint(position: Offset, timeMillis: Long) {
        if (inputBuffer.append(position.inputPoint(timeMillis))) {
            markInputChanged()
        }
    }

    fun endStroke() {
        if (inputBuffer.end()) {
            markInputChanged()
            scheduleRecognition()
        }
    }

    fun clear() {
        clear(resetOwnership = true)
    }

    private fun clear(resetOwnership: Boolean) {
        recognitionJob?.cancel()
        recognitionJob = null
        inputBuffer.clear()
        inputRevision += 1
        if (resetOwnership) requestOwnership.inputChanged()
        candidates = emptyList()
        candidateStamp = null
        statusMessage = null
        isUsingCloud = false
    }

    fun destroy() {
        panelActive = false
        clear()
        runCatching { recognizer?.close() }
        recognizer = null
        model = null
        configuredLanguageTag = null
        configurationGeneration += 1
        modelReady = false
        isModelDownloading = false
        isUsingCloud = false
    }

    /** Checks model availability and starts the download when needed. */
    fun prepareModel() {
        if (!panelActive) return
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
                if (generation != configurationGeneration || !panelActive) {
                    return@addOnSuccessListener
                }
                if (downloaded) {
                    modelReady = true
                    statusMessage = null
                    if (hasInk()) recognizeNow()
                } else {
                    downloadModel(manager, inkModel, generation)
                }
            }
            .addOnFailureListener { error ->
                if (generation != configurationGeneration || !panelActive) {
                    return@addOnFailureListener
                }
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
                if (generation != configurationGeneration || !panelActive) {
                    return@addOnSuccessListener
                }
                isModelDownloading = false
                modelReady = true
                statusMessage = null
                if (hasInk()) recognizeNow()
            }
            .addOnFailureListener { error ->
                if (generation != configurationGeneration || !panelActive) {
                    return@addOnFailureListener
                }
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
        if (!panelActive) return
        val generation = configureForCurrentLanguage()
        val stamp = requestOwnership.begin()
        val activeRecognizer = recognizer
        if (activeRecognizer == null) {
            recognizeWithCloud(generation, stamp)
            return
        }
        if (!modelReady) {
            prepareModel()
            return
        }
        if (!hasInk()) return
        val ink = buildInk() ?: return
        activeRecognizer.recognize(ink)
            .addOnSuccessListener { result ->
                if (
                    generation != configurationGeneration ||
                    activeRecognizer !== recognizer ||
                    !panelActive ||
                    !requestOwnership.isOwner(stamp)
                ) {
                    return@addOnSuccessListener
                }
                val recognizedCandidates = result.candidates
                    .map { it.text.trim() }
                    .filter { it.isNotEmpty() }
                    .distinct()
                    .take(3)
                if (!publicationAllowed(false)) {
                    candidates = emptyList()
                    candidateStamp = null
                    requestOwnership.finish(stamp)
                    return@addOnSuccessListener
                }
                candidates = recognizedCandidates
                candidateStamp = stamp.takeIf { candidates.isNotEmpty() }
                if (candidates.isEmpty()) {
                    recognizeWithCloud(generation, stamp)
                } else {
                    requestOwnership.finish(stamp)
                }
            }
            .addOnFailureListener { error ->
                if (
                    generation != configurationGeneration ||
                    activeRecognizer !== recognizer ||
                    !panelActive ||
                    !requestOwnership.isOwner(stamp)
                ) {
                    return@addOnFailureListener
                }
                if (!publicationAllowed(false)) {
                    candidates = emptyList()
                    candidateStamp = null
                    requestOwnership.finish(stamp)
                    return@addOnFailureListener
                }
                statusMessage = error.message
                recognizeWithCloud(generation, stamp)
            }
    }

    private fun recognizeWithCloud(generation: Int, stamp: HandwritingWorkStamp) {
        if (!hasInk() || isUsingCloud || !requestOwnership.isOwner(stamp)) return
        val png = renderInkPng()
        if (png == null) {
            statusMessage = "BuddyGrammar could not read that handwriting."
            return
        }
        recognitionJob = scope.launch {
            isUsingCloud = true
            statusMessage = "Asking AI…"
            val recognized = runCatching { cloudFallback(png) }
                .getOrNull()
                ?.trim()
                .orEmpty()
            if (
                generation != configurationGeneration ||
                !panelActive ||
                !requestOwnership.isOwner(stamp)
            ) return@launch
            isUsingCloud = false
            if (recognized.isNotEmpty() && publicationAllowed(true)) {
                candidates = (listOf(recognized) + candidates).distinct().take(3)
                candidateStamp = stamp
                statusMessage = null
            } else if (!publicationAllowed(false)) {
                candidates = emptyList()
                candidateStamp = null
                statusMessage = null
            } else if (candidates.isEmpty()) {
                statusMessage = cloudUnavailableMessage()
                    ?: "BuddyGrammar couldn't read that handwriting."
            }
            requestOwnership.finish(stamp)
        }
    }

    private fun renderInkPng(): ByteArray? {
        val strokes = finishedStrokes.filter(List<Offset>::isNotEmpty)
        if (strokes.isEmpty()) return null
        val points = strokes.flatten()
        val minX = points.minOf(Offset::x)
        val maxX = points.maxOf(Offset::x)
        val minY = points.minOf(Offset::y)
        val maxY = points.maxOf(Offset::y)
        val sourceWidth = (maxX - minX).coerceAtLeast(1f)
        val sourceHeight = (maxY - minY).coerceAtLeast(1f)
        val scale = min(
            (CLOUD_IMAGE_WIDTH - CLOUD_IMAGE_PADDING * 2) / sourceWidth,
            (CLOUD_IMAGE_HEIGHT - CLOUD_IMAGE_PADDING * 2) / sourceHeight,
        )
        val offsetX = (CLOUD_IMAGE_WIDTH - sourceWidth * scale) / 2f
        val offsetY = (CLOUD_IMAGE_HEIGHT - sourceHeight * scale) / 2f
        val bitmap = Bitmap.createBitmap(CLOUD_IMAGE_WIDTH, CLOUD_IMAGE_HEIGHT, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap).apply { drawColor(Color.WHITE) }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            style = Paint.Style.STROKE
            strokeWidth = CLOUD_STROKE_WIDTH
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        strokes.forEach { stroke ->
            val normalized = stroke.map { point ->
                Offset(
                    x = offsetX + (point.x - minX) * scale,
                    y = offsetY + (point.y - minY) * scale,
                )
            }
            if (normalized.size == 1) {
                canvas.drawCircle(
                    normalized.first().x,
                    normalized.first().y,
                    CLOUD_STROKE_WIDTH / 2f,
                    paint.apply { style = Paint.Style.FILL },
                )
                paint.style = Paint.Style.STROKE
            } else {
                val path = Path().apply {
                    moveTo(normalized.first().x, normalized.first().y)
                    normalized.drop(1).forEach { point -> lineTo(point.x, point.y) }
                }
                canvas.drawPath(path, paint)
            }
        }
        return ByteArrayOutputStream().use { output ->
            val encoded = bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            bitmap.recycle()
            output.toByteArray().takeIf { encoded && it.isNotEmpty() }
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
        candidateStamp = null
        runCatching { recognizer?.close() }
        recognizer = null
        model = null
        modelReady = false
        isModelDownloading = false
        isUsingCloud = false
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

    private fun buildInk(): Ink? {
        val strokes = inputBuffer.finishedStrokes
        if (strokes.isEmpty()) return null
        return Ink.builder().apply {
            strokes.forEach { stroke ->
                val strokeBuilder = Ink.Stroke.builder()
                stroke.forEach { point ->
                    strokeBuilder.addPoint(
                        Ink.Point.create(point.x, point.y, point.timeMillis),
                    )
                }
                addStroke(strokeBuilder.build())
            }
        }.build()
    }

    private fun Offset.inputPoint(timeMillis: Long): HandwritingInputPoint =
        HandwritingInputPoint(x = x, y = y, timeMillis = timeMillis)

    private fun hasInk(): Boolean = inputBuffer.hasFinishedStrokes

    private fun markInputChanged() {
        inputRevision += 1
        requestOwnership.inputChanged()
        candidates = emptyList()
        candidateStamp = null
        statusMessage = null
        isUsingCloud = false
    }

    private companion object {
        const val RECOGNITION_DEBOUNCE_MS = 800L
        const val CLOUD_IMAGE_WIDTH = 640
        const val CLOUD_IMAGE_HEIGHT = 256
        const val CLOUD_IMAGE_PADDING = 24f
        const val CLOUD_STROKE_WIDTH = 8f
    }
}
