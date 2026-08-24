package com.francescooddo.buddygrammar.ime

import android.Manifest
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.os.SystemClock
import android.speech.SpeechRecognizer
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import android.view.inputmethod.InputMethodSubtype
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.ComposeView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.francescooddo.buddygrammar.MainActivity
import com.francescooddo.buddygrammar.R
import com.francescooddo.buddygrammar.core.AndroidIcuGraphemeBoundaryProvider
import com.francescooddo.buddygrammar.core.AutomaticSuggestionReplacement
import com.francescooddo.buddygrammar.core.AutomaticSuggestionSource
import com.francescooddo.buddygrammar.core.BuddyGrammarApi
import com.francescooddo.buddygrammar.core.BuddySettings
import com.francescooddo.buddygrammar.core.BuddyRewriteIntent
import com.francescooddo.buddygrammar.core.CatalogPlane
import com.francescooddo.buddygrammar.core.CorrectionProposalEditorStamp
import com.francescooddo.buddygrammar.core.CorrectionProposalScope
import com.francescooddo.buddygrammar.core.CorrectionProposalTransaction
import com.francescooddo.buddygrammar.core.CorrectionCompositionEditor
import com.francescooddo.buddygrammar.core.CorrectionCompositionEffect
import com.francescooddo.buddygrammar.core.CorrectionCompositionRejection
import com.francescooddo.buddygrammar.core.CorrectionCompositionReceiptMode
import com.francescooddo.buddygrammar.core.CorrectionCompositionSession
import com.francescooddo.buddygrammar.core.CorrectionUndoState
import com.francescooddo.buddygrammar.core.HandwritingTextFormatter
import com.francescooddo.buddygrammar.core.GraphemeClusterOffsets
import com.francescooddo.buddygrammar.core.LanguageSupport
import com.francescooddo.buddygrammar.core.LiveLearningResetState
import com.francescooddo.buddygrammar.core.KeyboardCatalog
import com.francescooddo.buddygrammar.core.KeyboardDeletionPolicy
import com.francescooddo.buddygrammar.core.KeyboardLatencyMetric
import com.francescooddo.buddygrammar.core.KeyboardLatencyRecorder
import com.francescooddo.buddygrammar.core.KeyboardOwnedWordProvenancePolicy
import com.francescooddo.buddygrammar.core.LocalCorrectionRevertMode
import com.francescooddo.buddygrammar.core.ObservedTextSuffix
import com.francescooddo.buddygrammar.core.PersonalLanguageModel
import com.francescooddo.buddygrammar.core.PreferencesRepository
import com.francescooddo.buddygrammar.core.RankedLanguageLexiconLoader
import com.francescooddo.buddygrammar.core.ReturnIntent
import com.francescooddo.buddygrammar.core.ReviewableCorrectionProposal
import com.francescooddo.buddygrammar.core.Suggestion
import com.francescooddo.buddygrammar.core.SuggestionApplicationEditor
import com.francescooddo.buddygrammar.core.SuggestionApplicationTransaction
import com.francescooddo.buddygrammar.core.SuggestionCommittedContext
import com.francescooddo.buddygrammar.core.SuggestionEngine
import com.francescooddo.buddygrammar.core.SuggestionKind
import com.francescooddo.buddygrammar.core.SuggestionRenderReceipt
import com.francescooddo.buddygrammar.core.SuggestionTargetBoundaryPolicy
import com.francescooddo.buddygrammar.core.SwipePathSample
import com.francescooddo.buddygrammar.core.SwipeVocabulary
import com.francescooddo.buddygrammar.core.TextCorrectionCandidate
import com.francescooddo.buddygrammar.core.TextContextExtractor
import com.francescooddo.buddygrammar.core.TextInsertionFormatter
import com.francescooddo.buddygrammar.core.WordTokenNormalizer
import com.francescooddo.buddygrammar.core.adaptive.ActivePracticeSession
import com.francescooddo.buddygrammar.core.adaptive.AdaptivePracticeStore
import com.francescooddo.buddygrammar.core.adaptive.KeyCandidate
import com.francescooddo.buddygrammar.core.adaptive.OutcomeEvidence
import com.francescooddo.buddygrammar.core.adaptive.TapPoint
import com.francescooddo.buddygrammar.core.adaptive.TapWordDecoder
import com.francescooddo.buddygrammar.core.adaptive.TapWordAcceptancePolicy
import com.francescooddo.buddygrammar.core.adaptive.TapWordLatticeTap
import com.francescooddo.buddygrammar.core.adaptive.TypingContext
import com.francescooddo.buddygrammar.core.adaptive.TypingIntelligence
import com.francescooddo.buddygrammar.core.adaptive.TypingOutcome
import com.francescooddo.buddygrammar.core.adaptive.TypingPolicy
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale
import java.util.UUID
import kotlin.math.abs

data class KeyboardStatus(val message: String, val isError: Boolean = false)

/** Records durable user evidence only after a receipt-backed revert succeeds. */
internal fun recordAutomaticCorrectionRejection(
    personalModel: PersonalLanguageModel,
    rejection: CorrectionCompositionRejection,
) {
    val previousWord = rejection.precedingContext
        .trimEnd()
        .takeLastWhile(WordTokenNormalizer::isWordCharacter)
        .let(WordTokenNormalizer::canonicalize)
    personalModel.reject(
        previousWord = previousWord.takeIf(String::isNotEmpty),
        word = rejection.rejectedText,
        languageTag = rejection.languageTag,
    )
    personalModel.learnCommittedText(
        text = rejection.restoredText,
        contextBeforeText = rejection.precedingContext,
        languageTag = rejection.languageTag,
    )
    personalModel.persist()
}

private class InputConnectionCorrectionEditor(
    private val connection: InputConnection,
    private val contextReader: (Int) -> String?,
    private val requiredContextSuffix: String? = null,
    private val requiredExactContext: String? = null,
    private val exactContextMaximum: Int = 512,
) : CorrectionCompositionEditor {
    override val correctionCompositionText: String
        get() = contextReader(512).orEmpty()

    override fun replaceCorrectionCompositionSuffix(
        expectedSuffix: String,
        replacement: String,
    ): Boolean {
        connection.beginBatchEdit()
        return try {
            val observedContext = contextReader(
                if (requiredExactContext == null) 512 else exactContextMaximum,
            ) ?: return false
            if (requiredExactContext != null && observedContext != requiredExactContext) {
                return false
            }
            if (!observedContext.endsWith(expectedSuffix)) return false
            if (
                requiredContextSuffix != null &&
                !observedContext.endsWith(requiredContextSuffix)
            ) return false
            if (!connection.deleteSurroundingText(expectedSuffix.length, 0)) {
                false
            } else if (connection.commitText(replacement, 1)) {
                true
            } else {
                connection.commitText(expectedSuffix, 1)
                false
            }
        } finally {
            connection.endBatchEdit()
        }
    }

    // Ordinary deletion remains in the service's ICU grapheme-safe key path.
    override fun deleteCorrectionCompositionBackward(): Boolean = false
}

private class InputConnectionSuggestionEditor(
    private val connection: InputConnection,
    private val contextReader: (Int) -> String?,
) : SuggestionApplicationEditor {
    override fun beginBatchEdit() {
        connection.beginBatchEdit()
    }

    override fun contextBeforeCursor(maximumCharacters: Int): String? =
        contextReader(maximumCharacters)

    override fun deleteBeforeCursor(characters: Int): Boolean =
        connection.deleteSurroundingText(characters, 0)

    override fun commitText(text: String): Boolean = connection.commitText(text, 1)

    override fun endBatchEdit() {
        connection.endBatchEdit()
    }
}

private class CorrectionUndoEditor(
    private val connection: InputConnection,
    private val state: CorrectionUndoState,
    private val beforeReader: (Int) -> String?,
    private val afterReader: (Int) -> String?,
) : CorrectionCompositionEditor {
    override val correctionCompositionText: String
        get() {
            val before = beforeReader(
                state.anchorBefore.length + state.replacementText.length,
            ).orEmpty()
            val after = afterReader(state.anchorAfter.length).orEmpty()
            return state.replacementText.takeIf { state.matches(before, after) }.orEmpty()
        }

    override fun replaceCorrectionCompositionSuffix(
        expectedSuffix: String,
        replacement: String,
    ): Boolean {
        if (
            expectedSuffix != state.replacementText || replacement != state.originalText ||
            correctionCompositionText != expectedSuffix
        ) return false
        connection.beginBatchEdit()
        return try {
            if (!connection.deleteSurroundingText(state.replacementText.length, 0)) {
                false
            } else if (connection.commitText(state.originalText, 1)) {
                true
            } else {
                connection.commitText(state.replacementText, 1)
                false
            }
        } finally {
            connection.endBatchEdit()
        }
    }

    override fun deleteCorrectionCompositionBackward(): Boolean = false
}

class BuddyGrammarImeService :
    InputMethodService(),
    LifecycleOwner,
    ViewModelStoreOwner,
    SavedStateRegistryOwner {

    private val preferences by lazy { PreferencesRepository(this) }
    private lateinit var learningResetState: LiveLearningResetState
    private var personalModelBacking: PersonalLanguageModel? = null
    private val personalModel: PersonalLanguageModel
        get() = personalModelBacking ?: createPersonalLanguageModel().also {
            personalModelBacking = it
        }
    private val api = BuddyGrammarApi()
    private var typingIntelligenceBacking: TypingIntelligence? = null
    private val typingIntelligence: TypingIntelligence
        get() = typingIntelligenceBacking ?: TypingIntelligence(
            preferences.loadTypingProfile(),
        ).also { typingIntelligenceBacking = it }
    private val practiceStore by lazy { AdaptivePracticeStore(this) }
    private val keyboardLexicon by lazy { RankedLanguageLexiconLoader.bundled(resources) }
    private val tapWordDecoder by lazy { TapWordDecoder(keyboardLexicon) }
    private val graphemeClusterOffsets = GraphemeClusterOffsets(
        AndroidIcuGraphemeBoundaryProvider,
    )
    private val textContextExtractor = TextContextExtractor(
        AndroidIcuGraphemeBoundaryProvider,
    )
    private val keyboardDeletionPolicy = KeyboardDeletionPolicy(
        AndroidIcuGraphemeBoundaryProvider,
    )
    private val swipeTypingEngine by lazy { SwipeVocabulary.productionEngine(keyboardLexicon) }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var cachedSettings = BuddySettings()

    private val lifecycleRegistry = LifecycleRegistry(this)
    private val store = ViewModelStore()
    private val savedStateRegistryController = SavedStateRegistryController.create(this)

    override val lifecycle: Lifecycle get() = lifecycleRegistry
    override val viewModelStore: ViewModelStore get() = store
    override val savedStateRegistry: SavedStateRegistry
        get() = savedStateRegistryController.savedStateRegistry

    val keyboardState = KeyboardState()
    val handwriting by lazy {
        HandwritingController(
            scope = scope,
            languageTagProvider = { currentLanguageTag },
            cloudFallback = { png ->
                refreshEditorCapabilities()
                if (!editorCapabilities.cloudHandwriting.isAllowed) {
                    null
                } else {
                    api.recognizeHandwriting(
                        imagePng = png,
                        clientId = preferences.installationId(),
                        modelId = cachedSettings.activeModelId,
                        languageCode = currentLanguageTag,
                    )
                }
            },
            cloudUnavailableMessage = {
                editorCapabilities.cloudHandwriting
                    .takeUnless { it.isAllowed }
                    ?.denialMessage("AI handwriting")
            },
            publicationAllowed = { requiresCloud ->
                refreshEditorCapabilities()
                editorCapabilities.localHandwriting.isAllowed &&
                    (!requiresCloud || editorCapabilities.cloudHandwriting.isAllowed)
            },
        )
    }
    internal val voice by lazy {
        VoiceTypingController(
            context = this,
            onFinalText = ::commitDictatedText,
            onRequestFinished = ::finishVoiceRequest,
            isRequestOwner = ::isVoiceRequestOwner,
            onCancelled = voiceRequestOwnership::invalidate,
            languageTagProvider = { currentLanguageTag },
        )
    }

    var suggestions by mutableStateOf<List<Suggestion>>(emptyList())
        private set
    var status by mutableStateOf<KeyboardStatus?>(null)
        private set
    var editorCapabilities by mutableStateOf(EditorCapabilities.INACTIVE)
        private set
    var keyboardPresentation by mutableStateOf(
        KeyboardCatalog.presentation(
            fieldKind = EditorFieldKind.TEXT.catalogFieldKind,
            localeIdentifier = LanguageSupport.DEFAULT_LANGUAGE_TAG,
        ),
    )
        private set
    val secureField: Boolean get() = editorCapabilities.isSecureField
    var localCorrectionOriginalText by mutableStateOf<String?>(null)
        private set
    var reviewProposal by mutableStateOf<CorrectionProposalTransaction?>(null)
        private set
    var isCorrecting by mutableStateOf(false)
        private set
    var canUndoCorrection by mutableStateOf(false)
        private set
    var returnAction by mutableStateOf(EditorInfo.IME_ACTION_NONE)
        private set
    var hasMicPermission by mutableStateOf(false)
        private set

    private var correctionJob: Job? = null
    private var typingRefreshJob: Job? = null
    private val correctionRequestOwnership = CorrectionRequestOwnership()
    private val voiceRequestOwnership = VoiceRequestOwnership()
    private var correctionUndoJob: Job? = null
    private var localCorrectionReceiptJob: Job? = null
    private val correctionCompositionSession = CorrectionCompositionSession()
    private var pendingCorrectionUndo: CorrectionUndoState? = null
    private var pendingCorrectionLearning: PendingCorrectionLearning? = null
    private var pendingReviewSnapshot: CorrectionSnapshot? = null
    private var statusClearJob: Job? = null
    private var catalogLoadWarning: String? = null
    private var currentLanguageTag = LanguageSupport.DEFAULT_LANGUAGE_TAG
    private var capitalizationMode = EditorCapitalizationMode.NONE
    private val fieldEpoch: Long get() = correctionCompositionSession.snapshot.fieldEpoch
    private val fieldIdentifier: String
        get() = correctionCompositionSession.snapshot.fieldIdentifier
    private var selectionStart = -1
    private var selectionEnd = -1
    private var editorCursorPrimitiveAvailable = true
    private var editorContextPrimitiveAvailable = true
    private val observedTextSuffix = ObservedTextSuffix(SUGGESTION_CONTEXT)
    private var lastAdaptiveDecision: AdaptiveDecision? = null
    private var pendingRejectedDecision: AdaptiveDecision? = null
    private var adaptiveProfileDirty = false
    private var adaptiveObservationsSinceSave = 0
    private var activePracticeSession: ActivePracticeSession? = null
    private val currentWordTaps = mutableListOf<TapWordLatticeTap>()
    private var currentWordStartedAtProvenBoundary = false

    override fun onCreate() {
        super.onCreate()
        learningResetState = LiveLearningResetState(
            preferences.loadLearningResetGenerations(),
        )
        val catalogResult = runCatching {
            resources.openRawResource(R.raw.keyboard_catalog)
                .bufferedReader(Charsets.UTF_8)
                .use { reader -> reader.readText() }
        }.mapCatching { source ->
            KeyboardCatalog.installBundled(source).getOrThrow()
        }
        catalogLoadWarning = catalogResult.exceptionOrNull()?.let { error ->
            Log.e(LOG_TAG, "Bundled keyboard catalog failed validation; using safe fallback", error)
            CATALOG_FALLBACK_WARNING
        }
        savedStateRegistryController.performRestore(null)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_START)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
    }

    override fun onCreateInputView(): View {
        window?.window?.decorView?.let { decorView ->
            decorView.setViewTreeLifecycleOwner(this)
            decorView.setViewTreeViewModelStoreOwner(this)
            decorView.setViewTreeSavedStateRegistryOwner(this)
        }
        return ComposeView(this).apply {
            setViewTreeLifecycleOwner(this@BuddyGrammarImeService)
            setViewTreeViewModelStoreOwner(this@BuddyGrammarImeService)
            setViewTreeSavedStateRegistryOwner(this@BuddyGrammarImeService)
            setContent {
                KeyboardScreen(service = this@BuddyGrammarImeService)
            }
        }
    }

    override fun onEvaluateFullscreenMode(): Boolean = false

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        synchronizeLearningResetGenerations()
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        synchronizeLearningResetGenerations()
        suggestions = emptyList()
        invalidateVoiceRecognition()
        correctionCompositionSession.changeField(
            "${info?.packageName.orEmpty()}:${info?.fieldId ?: 0}:${fieldEpoch + 1}",
        )
        currentLanguageTag = resolveLanguageTag(info)
        selectionStart = info?.initialSelStart ?: -1
        selectionEnd = info?.initialSelEnd ?: -1
        editorCursorPrimitiveAvailable = true
        editorContextPrimitiveAvailable = true
        refreshEditorCapabilities(info)
        capitalizationMode = EditorCapitalizationPolicy.mode(
            inputType = info?.inputType ?: 0,
            fieldKind = editorCapabilities.presentationFieldKind,
        )
        activePracticeSession = practiceStore.loadActiveSession()
        clearCurrentWordTaps()
        lastAdaptiveDecision = null
        pendingRejectedDecision = null
        observedTextSuffix.clear()
        val startOnNumbers = keyboardPresentation.primaryPlane == CatalogPlane.NUMBERS
        keyboardState.configureForNewInput(
            startOnNumbers = startOnNumbers,
            autoCapitalize = capitalizationMode.shouldShift(""),
        )
        handwriting.changeField(fieldEpoch)
        returnAction = resolveReturnAction(info)
        hasMicPermission = hasMicrophonePermission()
        clearLocalCorrectionReceipt()
        clearReviewProposal()
        clearCorrectionUndo(acceptLearning = false)
        cancelCorrection()
        showBaselineStatus()
        refreshTypingState()
    }

    override fun onWindowShown() {
        super.onWindowShown()
        synchronizeLearningResetGenerations()
        hasMicPermission = hasMicrophonePermission()
        refreshEditorCapabilities()
        refreshTypingState()
    }

    override fun onCurrentInputMethodSubtypeChanged(newSubtype: InputMethodSubtype) {
        super.onCurrentInputMethodSubtypeChanged(newSubtype)
        // Finish any receipt while its original language still owns the learning event,
        // then discard every transient whose ranking or text interpretation is language-bound.
        synchronizeLearningResetGenerations()
        persistAdaptiveProfile(force = true)
        invalidateVoiceRecognition()
        clearLocalCorrectionReceipt(acceptLearning = true)
        clearReviewProposal()
        clearCorrectionUndo()
        cancelCorrection()
        clearCurrentWordTaps()
        observedTextSuffix.clear()
        suggestions = emptyList()
        lastAdaptiveDecision = null
        pendingRejectedDecision = null
        currentLanguageTag = resolveLanguageTag(currentInputEditorInfo, newSubtype)
        handwriting.languageChanged()
        refreshEditorCapabilities()
        refreshTypingState()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        teardownEndedField()
        super.onFinishInputView(finishingInput)
    }

    override fun onFinishInput() {
        teardownEndedField()
        super.onFinishInput()
    }

    /** Idempotent because Android may finish the view and input separately. */
    private fun teardownEndedField() {
        typingRefreshJob?.cancel()
        typingRefreshJob = null
        synchronizeLearningResetGenerations()
        persistAdaptiveProfile(force = true)
        lastAdaptiveDecision = null
        pendingRejectedDecision = null
        activePracticeSession = null
        clearCurrentWordTaps()
        personalModel.persist()
        clearLocalCorrectionReceipt(acceptLearning = false)
        clearReviewProposal()
        clearCorrectionUndo(acceptLearning = false)
        cancelCorrection()
        observedTextSuffix.clear()
        suggestions = emptyList()
        correctionCompositionSession.externalEditObserved()
        invalidateVoiceRecognition()
        handwriting.deactivate()
        clearStatus()
    }

    override fun onUpdateSelection(
        oldSelStart: Int,
        oldSelEnd: Int,
        newSelStart: Int,
        newSelEnd: Int,
        candidatesStart: Int,
        candidatesEnd: Int,
    ) {
        super.onUpdateSelection(
            oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd,
        )
        selectionStart = newSelStart
        selectionEnd = newSelEnd
        if (
            CorrectionLifecyclePolicy.selectionInvalidates(
                oldSelStart,
                oldSelEnd,
                newSelStart,
                newSelEnd,
            )
        ) {
            val hadPendingCorrection = isCorrecting || reviewProposal != null
            clearReviewProposal()
            cancelCorrection()
            if (hadPendingCorrection) showBaselineStatus()
        }
        if (canUndoCorrection && !correctionUndoStillMatches()) {
            clearCorrectionUndo()
        }
        if (
            correctionCompositionSession.snapshot.receiptMode ==
            CorrectionCompositionReceiptMode.AUTOMATIC
        ) {
            val connection = currentInputConnection
            if (
                connection == null || correctionCompositionSession.invalidateIfEditorChanged(
                    correctionEditor(connection),
                )
            ) {
                localCorrectionReceiptJob?.cancel()
                localCorrectionReceiptJob = null
                localCorrectionOriginalText = null
            }
        }
        scheduleTypingStateRefresh()
    }

    override fun onDestroy() {
        teardownEndedField()
        handwriting.destroy()
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_STOP)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        store.clear()
        scope.cancel()
        super.onDestroy()
    }

    // region Key handling

    fun onAdaptiveCharacterKey(value: String, x: Double, y: Double) {
        if (!editorCapabilities.suggestions.isAllowed || !editorCapabilities.readContext.isAllowed) {
            onCharacterKey(value)
            return
        }
        val literal = value.singleOrNull()?.lowercaseChar() ?: return onCharacterKey(value)
        var adaptiveContext: String? = null
        AdaptiveCharacterContextDispatch.dispatch(
            literalValue = value,
            contextBeforeCursor = readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT),
            commitLiteral = ::onCharacterKey,
            continueAdaptive = { adaptiveContext = it },
        )
        val before = adaptiveContext ?: return
        val now = SystemClock.elapsedRealtime()
        val policy = adaptiveTypingPolicy()
        pendingRejectedDecision
            ?.takeIf {
                activePracticeSession == null &&
                    now - it.createdAtMillis <= RETYPE_WINDOW_MS
            }
            ?.let { rejected ->
                typingIntelligence.observe(
                    TypingOutcome(
                        tap = rejected.tap,
                        intendedCharacter = literal,
                        evidence = OutcomeEvidence.EXPLICIT_RETYPE,
                        policy = rejected.policy,
                    ),
                )
                markAdaptiveProfileDirty()
            }
        pendingRejectedDecision = null

        val tap = TapPoint(x = x, y = y)
        val resolution = typingIntelligence.resolve(
            tap = tap,
            context = TypingContext(
                currentWordPrefix = WordTokenNormalizer.canonicalize(
                    before.takeLastWhile(WordTokenNormalizer::isWordCharacter),
                ),
                languageTag = currentLanguageTag,
                policy = policy,
            ),
        )
        if (
            policy == TypingPolicy.PRACTICE &&
            cachedSettings.personalizedPracticeEnabled
        ) {
            expectedPracticeCharacter(before.length)?.let { intendedCharacter ->
                typingIntelligence.observe(
                    TypingOutcome(
                        tap = tap,
                        intendedCharacter = intendedCharacter,
                        evidence = OutcomeEvidence.PRACTICE_TARGET,
                        policy = TypingPolicy.PRACTICE,
                    ),
                )
                markAdaptiveProfileDirty()
            }
        }
        recordCurrentWordTap(
            tap = TapWordLatticeTap(
                resolution = resolution,
                literalTap = literal,
            ),
            contextBeforeTap = before,
        )
        onCharacterKey(resolution.character.toString())
        lastAdaptiveDecision = AdaptiveDecision(tap, policy, now)
    }

    fun onLiteralCharacterKey(value: String) {
        val key = value.singleOrNull()?.takeIf(Char::isLetter)
            ?: return onCharacterKey(value)
        if (editorCapabilities.suggestions.isAllowed && editorCapabilities.readContext.isAllowed) {
            val before = readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT)
            recordCurrentWordTap(
                tap = TapWordLatticeTap(
                    literalKey = key,
                    resolvedKey = key,
                    candidates = listOf(
                        KeyCandidate(key, 1.0),
                    ),
                ),
                contextBeforeTap = before,
            )
        }
        onCharacterKey(value)
    }

    private fun recordCurrentWordTap(
        tap: TapWordLatticeTap,
        contextBeforeTap: String?,
    ) {
        if (currentWordTaps.size >= TapWordDecoder.MAXIMUM_TAPS) return
        if (currentWordTaps.isEmpty()) {
            currentWordStartedAtProvenBoundary =
                KeyboardOwnedWordProvenancePolicy.startedAtProvenBoundary(
                    contextBeforeFirstTap = contextBeforeTap,
                    selectionStart = selectionStart,
                )
        }
        currentWordTaps += tap
    }

    private fun clearCurrentWordTaps() {
        currentWordTaps.clear()
        currentWordStartedAtProvenBoundary = false
    }

    private fun removeLastCurrentWordTap() {
        if (currentWordTaps.isEmpty()) return
        currentWordTaps.removeAt(currentWordTaps.lastIndex)
        if (currentWordTaps.isEmpty()) currentWordStartedAtProvenBoundary = false
    }

    fun commitSwipe(samples: List<SwipePathSample>) {
        if (
            !editorCapabilities.swipe.isAllowed ||
            keyboardState.layer != KeyboardLayer.LETTERS ||
            samples.size < 2
        ) {
            return
        }
        val before = readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT) ?: return
        val previousWord = before
            .trimEnd()
            .takeLastWhile(WordTokenNormalizer::isWordCharacter)
            .let(WordTokenNormalizer::canonicalize)
            .takeIf(String::isNotEmpty)
        val recognition = KeyboardLatencyRecorder.production.measure(
            KeyboardLatencyMetric.SWIPE_DECODE,
        ) {
            swipeTypingEngine.recognize(
                samples = samples,
                limit = 3,
                previousWord = previousWord,
                languageTag = currentLanguageTag,
            )
        }

        localEdit(preserveObservedSuffix = true)
        clearCurrentWordTaps()
        fun displayWord(value: String): String = when {
            keyboardState.capsLock -> value.uppercase(Locale.ROOT)
            keyboardState.shift -> value.replaceFirstChar { it.uppercaseChar() }
            else -> value
        }
        val accepted = recognition.acceptedCandidate
        if (accepted == null) {
            suggestions = recognition.candidates.mapNotNull { candidate ->
                renderSuggestion(
                    suggestion = Suggestion(
                        text = displayWord(candidate.word),
                        replaceBeforeCursor = 0,
                        appendSpace = false,
                        kind = SuggestionKind.COMPLETION,
                    ),
                    contextBeforeCursor = before,
                )
            }
            setStatus("Swipe not recognized. Tap a suggestion or try again.")
            return
        }
        val word = displayWord(accepted.word)
        if (!commitObservedText(word)) return
        keyboardState.onCharacterCommitted()
        val contextAfterSwipe = readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT)
            ?: return

        suggestions = if (activePracticeSession == null && editorCapabilities.suggestions.isAllowed) {
            recognition.candidates.drop(1).mapNotNull { alternate ->
                if (!contextAfterSwipe.endsWith(word)) return@mapNotNull null
                val replacement = displayWord(alternate.word)
                val automaticReplacement = AutomaticSuggestionReplacement.create(
                    originalText = word,
                    replacementText = replacement,
                    boundaryText = "",
                    precedingContext = contextAfterSwipe.dropLast(word.length),
                    source = AutomaticSuggestionSource.SWIPE,
                )?.ownedBy(fieldEpoch, fieldIdentifier, currentLanguageTag)
                    ?: return@mapNotNull null
                renderSuggestion(
                    suggestion = Suggestion(
                        text = replacement,
                        replaceBeforeCursor = word.length,
                        appendSpace = false,
                        kind = SuggestionKind.CORRECTION,
                        automaticReplacement = automaticReplacement,
                    ),
                    contextBeforeCursor = contextAfterSwipe,
                    keyboardOwnedSuffix = word,
                )
            }
        } else {
            emptyList()
        }
    }

    fun onCharacterKey(value: String) {
        lastAdaptiveDecision = null
        pendingRejectedDecision = null
        val finishesWord = value.length == 1 && value[0] in WORD_BOUNDARY_PUNCTUATION
        localEdit(preserveObservedSuffix = finishesWord)
        var appliedCorrection: AppliedLocalCorrection? = null
        if (finishesWord) {
            val removedWhitespace = if (editorCapabilities.autoCorrection.isAllowed) {
                removeWhitespaceBeforePunctuation(value)
            } else {
                0
            }
            val alreadyProcessed = if (removedWhitespace > 0) {
                observedTextSuffix.clear()
                true
            } else {
                consumeObservedFinalWord()
            }
            if (!alreadyProcessed) {
                appliedCorrection = applyLocalWordCorrectionIfNeeded()
                if (appliedCorrection == null) learnCompletedWord()
            }
            clearCurrentWordTaps()
        } else if (value.any { !it.isLetter() && it != '\'' }) {
            clearCurrentWordTaps()
        }
        val text = if (keyboardState.layer == KeyboardLayer.LETTERS && keyboardState.uppercase) {
            value.uppercase()
        } else {
            value
        }
        val didCommitBoundary = currentInputConnection?.commitText(text, 1) == true
        recordLocalCorrection(
            appliedCorrection,
            boundaryText = text.takeIf { finishesWord && didCommitBoundary }.orEmpty(),
        )
        keyboardState.onCharacterCommitted()
        scheduleTypingStateRefresh()
    }

    fun onSpaceKey() {
        lastAdaptiveDecision = null
        pendingRejectedDecision = null
        localEdit(preserveObservedSuffix = true)
        val appliedCorrection = if (!consumeObservedFinalWord()) {
            val correction = applyLocalWordCorrectionIfNeeded()
            if (correction == null) learnCompletedWord()
            correction
        } else {
            null
        }
        clearCurrentWordTaps()
        val didCommitBoundary = currentInputConnection?.commitText(" ", 1) == true
        recordLocalCorrection(
            appliedCorrection,
            boundaryText = " ".takeIf { didCommitBoundary }.orEmpty(),
        )
        scheduleTypingStateRefresh()
    }

    fun onDeleteKey() {
        if (
            correctionCompositionSession.snapshot.receiptMode ==
                CorrectionCompositionReceiptMode.AUTOMATIC &&
            revertLocalCorrection(LocalCorrectionRevertMode.BACKSPACE)
        ) {
            return
        }
        lastAdaptiveDecision
            ?.takeIf { SystemClock.elapsedRealtime() - it.createdAtMillis <= RETYPE_WINDOW_MS }
            ?.let { pendingRejectedDecision = it }
        lastAdaptiveDecision = null
        localEdit()
        removeLastCurrentWordTap()
        val connection = currentInputConnection ?: return
        val before = readTextBeforeCursorForIntelligence(GRAPHEME_CONTEXT_UTF16)
        val deleteLength = before?.let { context ->
            graphemeClusterOffsets.utf16UnitsBeforeCursor(
                textBeforeCursor = context,
                graphemeCount = 1,
                // InputConnection may return fewer characters than requested
                // even when more text exists beyond the returned edge.
                leadingEdgeMayBeTruncated = true,
            )
        }
        val deleted = deleteLength
            ?.takeIf { it > 0 }
            ?.let { length ->
                runCatching { connection.deleteSurroundingText(length, 0) }.getOrDefault(false)
            }
            ?: false
        if (!deleted) {
            connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
            connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
        }
        scheduleTypingStateRefresh()
    }

    fun onDeleteWordKey() {
        lastAdaptiveDecision = null
        pendingRejectedDecision = null
        localEdit()
        clearCurrentWordTaps()
        val connection = currentInputConnection ?: return
        val before = readTextBeforeCursorForIntelligence(MAX_WORD_DELETE_CONTEXT)
        val utf16Units = keyboardDeletionPolicy.utf16UnitsBeforeCursor(
            textBeforeCursor = before.orEmpty(),
            leadingEdgeMayBeTruncated = true,
        )
        val deleted = utf16Units
            ?.takeIf { it > 0 }
            ?.let { length ->
                runCatching { connection.deleteSurroundingText(length, 0) }.getOrDefault(false)
            }
            ?: false
        if (!deleted) {
            sendWordDeleteKeyEvent(connection)
        }
        scheduleTypingStateRefresh()
    }

    fun moveCursorBy(characterDelta: Int) {
        if (characterDelta == 0) return
        val capability = editorCapabilities.moveCursor
        if (!capability.isAllowed) {
            setStatus(capability.denialMessage("Cursor movement"), error = true)
            return
        }
        val connection = currentInputConnection ?: return
        localEdit()
        clearCurrentWordTaps()
        val graphemeCount = abs(characterDelta.toLong())
            .coerceAtMost(Int.MAX_VALUE.toLong())
            .toInt()

        val start = selectionStart
        val end = selectionEnd
        val target = when {
            start < 0 || end < 0 -> null
            start != end -> if (characterDelta < 0) minOf(start, end) else maxOf(start, end)
            characterDelta < 0 -> {
                val before = readTextBeforeCursorForIntelligence(GRAPHEME_CONTEXT_UTF16)
                before?.let { context ->
                    graphemeClusterOffsets.utf16UnitsBeforeCursor(
                        textBeforeCursor = context,
                        graphemeCount = graphemeCount,
                        leadingEdgeMayBeTruncated = true,
                    )
                }?.let { utf16Units -> start - utf16Units }
            }
            else -> {
                val after = readTextAfterCursorForIntelligence(GRAPHEME_CONTEXT_UTF16)
                after?.let { context ->
                    graphemeClusterOffsets.utf16UnitsAfterCursor(
                        textAfterCursor = context,
                        graphemeCount = graphemeCount,
                        trailingEdgeMayBeTruncated = true,
                    )
                }?.let { utf16Units -> start + utf16Units }
            }
        }

        val moved = target?.let { resolved ->
            runCatching {
                connection.setSelection(resolved.coerceAtLeast(0), resolved.coerceAtLeast(0))
            }.getOrDefault(false)
        } ?: false
        if (moved) {
            selectionStart = target
            selectionEnd = target
            refreshTypingState()
            return
        }

        val fallbackWorked = sendCursorKeyEvents(connection, characterDelta)
        if (!fallbackWorked) {
            editorCursorPrimitiveAvailable = false
            refreshEditorCapabilities()
            setStatus(
                editorCapabilities.moveCursor.denialMessage("Cursor movement"),
                error = true,
            )
        }
    }

    fun onReturnKey() {
        lastAdaptiveDecision = null
        pendingRejectedDecision = null
        localEdit(preserveObservedSuffix = true)
        val appliedCorrection = if (!consumeObservedFinalWord()) {
            val correction = applyLocalWordCorrectionIfNeeded()
            if (correction == null) learnCompletedWord()
            correction
        } else {
            null
        }
        clearCurrentWordTaps()
        val action = returnAction
        val handledAction = action != EditorInfo.IME_ACTION_NONE &&
            action != EditorInfo.IME_ACTION_UNSPECIFIED &&
            currentInputConnection?.performEditorAction(action) == true
        val didCommitNewline = !handledAction && currentInputConnection?.commitText("\n", 1) == true
        recordLocalCorrection(
            appliedCorrection,
            boundaryText = "\n".takeIf { didCommitNewline }.orEmpty(),
        )
        scheduleTypingStateRefresh()
    }

    fun onShiftKey() {
        keyboardState.onShiftTapped()
    }

    fun setLayer(layer: KeyboardLayer) {
        refreshEditorCapabilities()
        val requestedCapability = when (layer) {
            KeyboardLayer.VOICE -> editorCapabilities.voice
            KeyboardLayer.HANDWRITING -> editorCapabilities.localHandwriting
            KeyboardLayer.LATEX -> editorCapabilities.literalTools
            else -> CapabilityDecision.ALLOWED
        }
        if (!requestedCapability.isAllowed) {
            val feature = when (layer) {
                KeyboardLayer.VOICE -> "Voice typing"
                KeyboardLayer.HANDWRITING -> "Handwriting"
                KeyboardLayer.LATEX -> "LaTeX"
                else -> "This tool"
            }
            setStatus(requestedCapability.denialMessage(feature), error = true)
            return
        }
        if (keyboardState.layer == KeyboardLayer.VOICE && layer != KeyboardLayer.VOICE) {
            invalidateVoiceRecognition()
        }
        if (keyboardState.layer == KeyboardLayer.HANDWRITING && layer != KeyboardLayer.HANDWRITING) {
            handwriting.deactivate()
        }
        keyboardState.switchLayer(layer)
        clearCurrentWordTaps()
        when (layer) {
            KeyboardLayer.HANDWRITING -> handwriting.activate(fieldEpoch)
            KeyboardLayer.LETTERS -> refreshTypingState()
            else -> Unit
        }
    }

    fun toggleVoiceListening() {
        if (keyboardState.layer != KeyboardLayer.VOICE) return
        if (voice.isListening) {
            voice.stopListening()
            return
        }
        refreshEditorCapabilities()
        if (!editorCapabilities.voice.isAllowed) {
            setStatus(editorCapabilities.voice.denialMessage("Voice typing"), error = true)
            return
        }
        if (!hasMicrophonePermission()) {
            hasMicPermission = false
            setStatus("Microphone permission is required for dictation.", error = true)
            return
        }
        val request = voiceRequestOwnership.begin(fieldEpoch)
        voice.startListening(request)
    }

    fun switchKeyboard() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && shouldOfferSwitchingToNextInputMethod()) {
            switchToNextInputMethod(false)
        } else {
            getSystemService(InputMethodManager::class.java).showInputMethodPicker()
        }
    }

    fun insertClipboardText() {
        refreshEditorCapabilities()
        val capability = editorCapabilities.clipboardInsertion
        if (!capability.isAllowed) {
            setStatus(capability.denialMessage("Clipboard"), error = true)
            return
        }
        val clipboard = getSystemService(ClipboardManager::class.java)
        val clip = clipboard.primaryClip
        val text = clip
            ?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)
            ?.coerceToText(this)
            ?.toString()
            .orEmpty()
        if (text.isEmpty()) {
            setStatus("The clipboard is empty.", error = true)
            return
        }
        localEdit()
        clearCurrentWordTaps()
        val connection = currentInputConnection ?: return
        if (connection.commitText(text, 1)) {
            refreshTypingState()
        } else {
            setStatus("The editor rejected the clipboard text.", error = true)
        }
    }

    fun openBuddyGrammarSettings() {
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            },
        )
    }

    fun applySuggestion(suggestion: Suggestion) {
        refreshEditorCapabilities()
        if (!editorCapabilities.suggestions.isAllowed || !editorCapabilities.readContext.isAllowed) {
            suggestions = emptyList()
            return
        }
        val renderReceipt = suggestion.renderReceipt
        if (
            renderReceipt == null ||
            !renderReceipt.ownsAndDescribes(
                suggestion = suggestion,
                currentFieldEpoch = fieldEpoch,
                currentFieldIdentifier = fieldIdentifier,
                currentLanguageTag = currentLanguageTag,
            )
        ) {
            suggestions = emptyList()
            refreshTypingState()
            return
        }
        val connection = currentInputConnection ?: return
        val insertion = suggestion.text + if (suggestion.appendSpace) " " else ""
        val automaticReplacement = suggestion.automaticReplacement
        if (automaticReplacement != null) {
            val before = readTextBeforeCursorForIntelligence(
                renderReceipt.maximumContextLength,
            )
            if (
                before == null ||
                !renderReceipt.matches(
                    suggestion = suggestion,
                    contextBeforeCursor = before,
                    currentFieldEpoch = fieldEpoch,
                    currentFieldIdentifier = fieldIdentifier,
                    currentLanguageTag = currentLanguageTag,
                ) ||
                suggestion.kind != SuggestionKind.CORRECTION ||
                !automaticReplacement.isOwnedBy(
                    fieldEpoch,
                    fieldIdentifier,
                    currentLanguageTag,
                ) ||
                !automaticReplacement.matches(
                    contextBeforeCursor = before,
                    replaceBeforeCursor = suggestion.replaceBeforeCursor,
                    insertion = insertion,
                )
            ) {
                suggestions = emptyList()
                refreshTypingState()
                return
            }

            localEdit()
            clearCurrentWordTaps()
            val now = SystemClock.elapsedRealtime()
            val correction = AppliedLocalCorrection(
                originalText = automaticReplacement.originalText,
                replacementText = automaticReplacement.replacementText,
                precedingContext = automaticReplacement.precedingContext,
                languageTag = currentLanguageTag,
                source = automaticReplacement.source.receiptValue,
            )
            val effect = correctionCompositionSession.applyAutomatic(
                editor = correctionEditor(
                    connection = connection,
                    requiredContextSuffix = automaticReplacement.expectedContextBeforeCursor,
                    renderReceipt = renderReceipt,
                ),
                originalText = correction.originalText,
                replacementText = correction.replacementText,
                boundaryText = automaticReplacement.boundaryText,
                precedingContext = correction.precedingContext,
                languageTag = correction.languageTag,
                source = correction.source,
                atMilliseconds = now,
            )
            if (effect.didMutateEditor) {
                val hasReceipt = !effect.ignored && activateLocalCorrectionReceipt(now)
                if (!hasReceipt) learnAppliedCorrection(correction)
                observeCommittedText(automaticReplacement.insertion)
            } else {
                suggestions = emptyList()
            }
            refreshTypingState()
            return
        }

        val preflightContext = readTextBeforeCursorForIntelligence(
            renderReceipt.maximumContextLength,
        )
        if (
            preflightContext == null ||
            !renderReceipt.matches(
                suggestion = suggestion,
                contextBeforeCursor = preflightContext,
                currentFieldEpoch = fieldEpoch,
                currentFieldIdentifier = fieldIdentifier,
                currentLanguageTag = currentLanguageTag,
            )
        ) {
            suggestions = emptyList()
            refreshTypingState()
            return
        }

        // Finalize older receipt-backed state while its original editor context still matches.
        localEdit()
        clearCurrentWordTaps()
        var committedContext: SuggestionCommittedContext? = null
        val effect = SuggestionApplicationTransaction.apply(
            suggestion = suggestion,
            currentFieldEpoch = fieldEpoch,
            currentFieldIdentifier = fieldIdentifier,
            currentLanguageTag = currentLanguageTag,
            editor = InputConnectionSuggestionEditor(
                connection = connection,
                contextReader = ::readTextBeforeCursorForIntelligence,
            ),
            onCommitted = { committedContext = it },
        )
        if (!effect.didMutateEditor) {
            suggestions = emptyList()
            refreshTypingState()
            return
        }
        if (
            !suggestion.isEmoji && editorCapabilities.learning.isAllowed &&
            activePracticeSession == null
        ) {
            committedContext?.let { committed ->
                personalModel.learnCommittedText(
                    committed.text,
                    committed.precedingContext,
                    committed.languageTag,
                )
            }
        }
        observeCommittedText(renderReceipt.insertion)
        refreshTypingState()
    }

    fun addCorrectionCandidateToDictionary(suggestion: Suggestion): Boolean {
        refreshEditorCapabilities()
        val result = CorrectionPreferenceActionPolicy.perform(
            capabilities = editorCapabilities,
            suggestion = suggestion,
            currentFieldEpoch = fieldEpoch,
            currentFieldIdentifier = fieldIdentifier,
            currentLanguageTag = currentLanguageTag,
            contextBeforeCursor = {
                readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT)
            },
            persist = { target ->
                personalModel.addToDictionary(target.typedText, target.languageTag).also { added ->
                    if (added) personalModel.persist()
                }
            },
        )
        return when (result) {
            is CorrectionPreferenceActionResult.Denied -> {
                suggestions = emptyList()
                setStatus(result.message, error = true)
                refreshTypingState()
                false
            }
            is CorrectionPreferenceActionResult.Applied -> {
                localEdit()
                refreshTypingState()
                setStatus(
                    if (result.changed) {
                        "Added “${result.target.typedText}” to your dictionary."
                    } else {
                        "“${result.target.typedText}” is already in your dictionary."
                    },
                )
                true
            }
        }
    }

    fun neverSuggestCorrection(suggestion: Suggestion): Boolean {
        refreshEditorCapabilities()
        val result = CorrectionPreferenceActionPolicy.perform(
            capabilities = editorCapabilities,
            suggestion = suggestion,
            currentFieldEpoch = fieldEpoch,
            currentFieldIdentifier = fieldIdentifier,
            currentLanguageTag = currentLanguageTag,
            contextBeforeCursor = {
                readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT)
            },
            persist = { target ->
                personalModel.suppressCorrection(
                    typed = target.typedText,
                    suggestion = target.suggestedText,
                    languageTag = target.languageTag,
                ).also { suppressed ->
                    if (suppressed) personalModel.persist()
                }
            },
        )
        return when (result) {
            is CorrectionPreferenceActionResult.Denied -> {
                suggestions = emptyList()
                setStatus(result.message, error = true)
                refreshTypingState()
                false
            }
            is CorrectionPreferenceActionResult.Applied -> {
                localEdit()
                refreshTypingState()
                setStatus(
                    if (result.changed) {
                        "Never suggesting “${result.target.suggestedText}” for " +
                            "“${result.target.typedText}”."
                    } else {
                        "That exact correction is already suppressed."
                    },
                )
                true
            }
        }
    }

    fun canOfferCorrectionPreferenceActions(suggestion: Suggestion): Boolean =
        CorrectionPreferenceActionPolicy.canOffer(
            capabilities = editorCapabilities,
            suggestion = suggestion,
            currentFieldEpoch = fieldEpoch,
            currentFieldIdentifier = fieldIdentifier,
            currentLanguageTag = currentLanguageTag,
        )

    fun commitEmoji(emoji: String) {
        refreshEditorCapabilities()
        val capability = editorCapabilities.directLocalInsertion
        if (!capability.isAllowed) {
            setStatus(capability.denialMessage("Emoji"), error = true)
            return
        }
        localEdit()
        clearCurrentWordTaps()
        currentInputConnection?.commitText(emoji, 1)
        refreshTypingState()
    }

    fun insertLatex(text: String) {
        refreshEditorCapabilities()
        val capability = editorCapabilities.literalTools
        if (!capability.isAllowed) {
            setStatus(capability.denialMessage("LaTeX"), error = true)
            return
        }
        onCharacterKey(text)
    }

    fun commitHandwriting(text: String) {
        refreshEditorCapabilities()
        val capability = editorCapabilities.localHandwriting
        if (!capability.isAllowed) {
            setStatus(capability.denialMessage("Handwriting"), error = true)
            return
        }
        val ownedText = handwriting.consumeCandidate(text, fieldEpoch) ?: run {
            setStatus("The field or handwriting changed. Write it again.", error = true)
            return
        }
        localEdit(preserveObservedSuffix = true)
        clearCurrentWordTaps()
        val before = readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT)
        val formatted = HandwritingTextFormatter.textForInsertion(
            ownedText,
            before,
            currentLanguageTag,
        )
        if (commitObservedText(formatted)) {
            handwriting.clear()
        } else {
            setStatus("The editor rejected the handwriting text. Try again.", error = true)
        }
        refreshTypingState()
    }

    private fun isVoiceRequestOwner(request: VoiceRequestToken): Boolean =
        voiceRequestOwnership.isOwner(
            request = request,
            currentFieldEpoch = fieldEpoch,
            voiceLayerActive = keyboardState.layer == KeyboardLayer.VOICE,
        )

    private fun finishVoiceRequest(request: VoiceRequestToken): Boolean =
        voiceRequestOwnership.finish(
            request = request,
            currentFieldEpoch = fieldEpoch,
            voiceLayerActive = keyboardState.layer == KeyboardLayer.VOICE,
        )

    private fun commitDictatedText(request: VoiceRequestToken, text: String): Boolean {
        if (!finishVoiceRequest(request)) return false
        if (!editorCapabilities.voice.isAllowed) return true
        localEdit(preserveObservedSuffix = true)
        clearCurrentWordTaps()
        val committed = commitObservedText(text.trim())
        if (!committed) setStatus("The editor rejected the dictation.", error = true)
        refreshTypingState()
        return true
    }

    private fun invalidateVoiceRecognition() {
        voice.cancel()
    }

    // endregion

    // region Microphone permission

    fun hasMicrophonePermission(): Boolean = ContextCompat.checkSelfPermission(
        this,
        Manifest.permission.RECORD_AUDIO,
    ) == PackageManager.PERMISSION_GRANTED

    fun openAppForMicrophonePermission() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(MainActivity.EXTRA_REQUEST_RECORD_AUDIO, true)
        }
        startActivity(intent)
    }

    // endregion

    // region Reviewable cloud correction

    fun correctCurrentText(intent: BuddyRewriteIntent = BuddyRewriteIntent.FIX) {
        refreshEditorCapabilities()
        clearLocalCorrectionReceipt(acceptLearning = true)
        clearReviewProposal()
        clearCorrectionUndo()
        cancelCorrection()
        val capability = editorCapabilities.starCorrection
        if (!capability.isAllowed) {
            setStatus(capability.denialMessage("★ correction"), error = true)
            return
        }
        if (!editorCapabilities.readContext.isAllowed) {
            setStatus(editorCapabilities.readContext.denialMessage("★ correction"), error = true)
            return
        }
        val settings = cachedSettings
        val snapshot = captureSnapshot()
        refreshEditorCapabilities()
        if (!editorCapabilities.allowsCloudCorrectionDispatch()) {
            val denied = if (!editorCapabilities.starCorrection.isAllowed) {
                editorCapabilities.starCorrection
            } else {
                editorCapabilities.readContext
            }
            setStatus(denied.denialMessage("★ correction"), error = true)
            return
        }
        if (snapshot == null) {
            setStatus("Type some text first.", error = true)
            return
        }
        val correctionAsyncStamp = correctionCompositionSession.captureAsyncStamp()

        setStatus("${intent.title}…", transient = false)
        isCorrecting = true
        val requestId = correctionRequestOwnership.begin()
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                val corrected = api.correct(
                    text = snapshot.candidate.requestText,
                    clientId = preferences.installationId(),
                    modelId = settings.activeModelId,
                    instruction = intent.instruction(settings.correctionInstruction),
                )
                if (
                    !correctionRequestOwnership.isOwner(requestId) ||
                    !correctionCompositionSession.isFresh(correctionAsyncStamp)
                ) return@launch
                val replacement = snapshot.candidate.replacement(corrected)
                when {
                    !snapshotStillMatches(snapshot) -> setStatus(
                        "The text or field changed, so the proposal was discarded.",
                        error = true,
                    )
                    replacement == snapshot.candidate.capturedText -> {
                        setStatus("No changes suggested.")
                    }
                    else -> {
                        val transaction = CorrectionProposalTransaction(
                            proposal = ReviewableCorrectionProposal(
                                intent = intent,
                                originalText = snapshot.candidate.capturedText,
                                proposedText = replacement,
                            ),
                            scope = when (snapshot.target) {
                                CorrectionTarget.Selection -> CorrectionProposalScope.SELECTION
                                CorrectionTarget.CurrentSentence ->
                                    CorrectionProposalScope.CURRENT_SENTENCE
                            },
                            stamp = snapshot.editorStamp(),
                        )
                        pendingReviewSnapshot = snapshot
                        reviewProposal = transaction
                        clearStatus()
                    }
                }
            } catch (_: CancellationException) {
                // Editing intentionally cancels an obsolete correction request.
            } catch (error: Throwable) {
                if (correctionRequestOwnership.isOwner(requestId)) {
                    setStatus(error.message ?: "Correction failed.", error = true)
                }
            } finally {
                if (correctionRequestOwnership.finish(requestId)) {
                    isCorrecting = false
                    correctionJob = null
                }
            }
        }
        correctionJob = job
        job.start()
    }

    fun acceptReviewProposal(id: UUID) {
        refreshEditorCapabilities()
        if (!editorCapabilities.starCorrection.isAllowed || !editorCapabilities.readContext.isAllowed) {
            clearReviewProposal()
            setStatus("The editor no longer allows this correction.", error = true)
            return
        }
        val transaction = reviewProposal?.takeIf { it.proposal.id == id } ?: return
        val snapshot = pendingReviewSnapshot ?: run {
            clearReviewProposal()
            return
        }
        val replacement = transaction.replacementIfFresh(
            currentProposalObservation(transaction.stamp),
        )
        if (replacement == null || !snapshotStillMatches(snapshot)) {
            clearReviewProposal()
            setStatus("The text or field changed, so this proposal is no longer valid.", error = true)
            return
        }

        val didApply = applyCorrection(snapshot, replacement)
        clearReviewProposal()
        if (didApply) {
            observeCommittedText(replacement)
            val settings = cachedSettings
            beginCorrectionUndo(
                state = CorrectionUndoState(
                    originalText = snapshot.candidate.capturedText,
                    replacementText = replacement,
                    anchorBefore = snapshot.anchorBefore,
                    anchorAfter = snapshot.anchorAfter,
                ),
                durationSeconds = settings.correctionUndoDurationSeconds,
                learning = PendingCorrectionLearning(
                    text = replacement,
                    precedingContext = snapshot.anchorBefore,
                    languageTag = snapshot.languageTag,
                ),
            )
        }
        setStatus(
            if (didApply) {
                "${transaction.proposal.intent.title} applied."
            } else {
                "The editor rejected this proposal."
            },
            error = !didApply,
        )
        refreshTypingState()
    }

    fun dismissReviewProposal(id: UUID) {
        val transaction = reviewProposal?.takeIf { it.proposal.id == id } ?: return
        clearReviewProposal()
        setStatus("${transaction.proposal.intent.title} dismissed.")
    }

    private fun captureSnapshot(): CorrectionSnapshot? {
        if (currentInputConnection == null) return null
        val selected = readSelectedTextForIntelligence()
        if (!editorCapabilities.readContext.isAllowed) return null
        val selectedCandidate = TextCorrectionCandidate.from(selected.orEmpty())
        when (
            CorrectionCaptureTargetPolicy.target(
                selectionStart = selectionStart,
                selectionEnd = selectionEnd,
                hasSelectedCandidate = selectedCandidate != null,
            )
        ) {
            CorrectionCaptureTarget.SELECTION -> {
                val candidate = selectedCandidate ?: return null
                val anchorBefore = readTextBeforeCursorForIntelligence(ANCHOR_LENGTH)
                    ?: return null
                val anchorAfter = readTextAfterCursorForIntelligence(ANCHOR_LENGTH)
                    ?: return null
                return CorrectionSnapshot(
                    fieldEpoch = fieldEpoch,
                    languageTag = currentLanguageTag,
                    target = CorrectionTarget.Selection,
                    candidate = candidate,
                    textBeforeCursor = "",
                    textAfterCursor = "",
                    anchorBefore = anchorBefore,
                    anchorAfter = anchorAfter,
                )
            }
            CorrectionCaptureTarget.UNAVAILABLE -> return null
            CorrectionCaptureTarget.CURRENT_SENTENCE -> Unit
        }
        val before = readTextBeforeCursorForIntelligence(CORRECTION_CONTEXT_READ_LIMIT) ?: return null
        val after = readTextAfterCursorForIntelligence(CORRECTION_CONTEXT_READ_LIMIT) ?: return null
        val cursorCandidate = textContextExtractor.currentSentence(
            contextBeforeCursor = before,
            contextAfterCursor = after,
            maximumCharacters = MAX_CONTEXT,
        ) ?: return null
        return CorrectionSnapshot(
            fieldEpoch = fieldEpoch,
            languageTag = currentLanguageTag,
            target = CorrectionTarget.CurrentSentence,
            candidate = cursorCandidate.candidate,
            textBeforeCursor = cursorCandidate.textBeforeCursor,
            textAfterCursor = cursorCandidate.textAfterCursor,
            anchorBefore = before
                .dropLast(cursorCandidate.textBeforeCursor.length)
                .takeLast(ANCHOR_LENGTH),
            anchorAfter = after
                .drop(cursorCandidate.textAfterCursor.length)
                .take(ANCHOR_LENGTH),
        )
    }

    private fun applyCorrection(snapshot: CorrectionSnapshot, replacement: String): Boolean {
        val connection = currentInputConnection ?: return false
        if (!snapshotStillMatches(snapshot)) return false
        connection.beginBatchEdit()
        try {
            return when (snapshot.target) {
                CorrectionTarget.Selection -> connection.commitText(replacement, 1)
                CorrectionTarget.CurrentSentence -> {
                    val deleted = connection.deleteSurroundingText(
                        snapshot.textBeforeCursor.length,
                        snapshot.textAfterCursor.length,
                    )
                    if (!deleted) {
                        false
                    } else if (connection.commitText(replacement, 1)) {
                        true
                    } else {
                        connection.commitText(snapshot.candidate.capturedText, 1)
                        false
                    }
                }
            }
        } finally {
            connection.endBatchEdit()
        }
    }

    private fun snapshotStillMatches(snapshot: CorrectionSnapshot): Boolean {
        if (snapshot.fieldEpoch != fieldEpoch) return false
        if (!editorCapabilities.readContext.isAllowed || currentInputConnection == null) return false
        return when (snapshot.target) {
            CorrectionTarget.Selection -> {
                readSelectedTextForIntelligence() == snapshot.candidate.capturedText &&
                    readTextBeforeCursorForIntelligence(ANCHOR_LENGTH) == snapshot.anchorBefore &&
                    readTextAfterCursorForIntelligence(ANCHOR_LENGTH) == snapshot.anchorAfter
            }
            CorrectionTarget.CurrentSentence -> {
                val expectedBefore = snapshot.anchorBefore + snapshot.textBeforeCursor
                val expectedAfter = snapshot.textAfterCursor + snapshot.anchorAfter
                readTextBeforeCursorForIntelligence(expectedBefore.length) == expectedBefore &&
                    readTextAfterCursorForIntelligence(expectedAfter.length) == expectedAfter
            }
        }
    }

    private fun CorrectionSnapshot.editorStamp(): CorrectionProposalEditorStamp = when (target) {
        CorrectionTarget.Selection -> CorrectionProposalEditorStamp(
            fieldEpoch = fieldEpoch,
            selectedText = candidate.capturedText,
            textBeforeCursor = anchorBefore,
            textAfterCursor = anchorAfter,
        )
        CorrectionTarget.CurrentSentence -> CorrectionProposalEditorStamp(
            fieldEpoch = fieldEpoch,
            selectedText = null,
            textBeforeCursor = anchorBefore + textBeforeCursor,
            textAfterCursor = textAfterCursor + anchorAfter,
        )
    }

    private fun currentProposalObservation(
        stamp: CorrectionProposalEditorStamp,
    ): CorrectionProposalEditorStamp? {
        val connection = currentInputConnection ?: return null
        return CorrectionProposalEditorStamp(
            fieldEpoch = fieldEpoch,
            selectedText = readSelectedTextForIntelligence()
                ?.takeIf(String::isNotEmpty),
            textBeforeCursor = readTextBeforeCursorForIntelligence(
                stamp.textBeforeCursor.length,
            ).orEmpty(),
            textAfterCursor = readTextAfterCursorForIntelligence(
                stamp.textAfterCursor.length,
            ).orEmpty(),
        )
    }

    fun undoLastCorrection() {
        refreshEditorCapabilities()
        if (!editorCapabilities.readContext.isAllowed) {
            clearCorrectionUndo(acceptLearning = false)
            setStatus(editorCapabilities.readContext.denialMessage("Undo"), error = true)
            return
        }
        val undo = pendingCorrectionUndo ?: return
        val connection = currentInputConnection
        if (connection == null) {
            clearCorrectionUndo(acceptLearning = false)
            setStatus("The text changed, so the correction could not be undone.", error = true)
            return
        }
        val effect = correctionCompositionSession.visibleRevert(
            correctionUndoEditor(connection, undo),
        )
        correctionUndoJob?.cancel()
        correctionUndoJob = null
        pendingCorrectionUndo = null
        pendingCorrectionLearning = null
        canUndoCorrection = false
        val didUndo = effect.didMutateEditor
        observedTextSuffix.clear()
        setStatus(
            if (didUndo) "Correction undone." else "The editor rejected Undo.",
            error = !didUndo,
        )
        refreshTypingState()
    }

    fun insertPendingTranscript() {
        refreshEditorCapabilities()
        localEdit(preserveObservedSuffix = true)
        val capability = editorCapabilities.pendingTranscript
        if (!capability.isAllowed) {
            setStatus(capability.denialMessage("saved dictation"), error = true)
            return
        }
        val transcript = preferences.loadPendingTranscript()
        if (transcript == null) {
            setStatus("No dictation is waiting. Record one in BuddyGrammar first.", error = true)
            return
        }
        if (commitObservedText(transcript.text, transcript.languageCode ?: currentLanguageTag)) {
            preferences.clearPendingTranscript()
            refreshEditorCapabilities()
            setStatus("Dictation inserted.")
        } else {
            setStatus("The editor rejected the dictation. It is still saved.", error = true)
        }
        refreshTypingState()
    }

    // endregion

    private fun localEdit(preserveObservedSuffix: Boolean = false) {
        typingRefreshJob?.cancel()
        typingRefreshJob = null
        clearLocalCorrectionReceipt(acceptLearning = true)
        clearReviewProposal()
        clearCorrectionUndo()
        cancelCorrection()
        if (!preserveObservedSuffix) observedTextSuffix.clear()
        showBaselineStatus()
    }

    private fun createPersonalLanguageModel(): PersonalLanguageModel {
        val generation = learningResetState.generations.personalLanguageModel
        return PersonalLanguageModel(
            initialData = preferences.loadPersonalLanguageModel(),
            onPersist = { data ->
                val saved = preferences.savePersonalLanguageModel(
                    data = data,
                    expectedResetGeneration = generation,
                )
                if (!saved) synchronizeLearningResetGenerations()
            },
        )
    }

    /** Drops live aggregates whenever Settings advances a persisted reset epoch. */
    private fun synchronizeLearningResetGenerations() {
        if (!::learningResetState.isInitialized) return
        val changes = learningResetState.reconcile(
            preferences.loadLearningResetGenerations(),
        )
        if (!changes.hasChanges) return

        if (changes.personalLanguageModelChanged) {
            localCorrectionReceiptJob?.cancel()
            localCorrectionReceiptJob = null
            localCorrectionOriginalText = null
            correctionUndoJob?.cancel()
            correctionUndoJob = null
            pendingCorrectionUndo = null
            pendingCorrectionLearning = null
            canUndoCorrection = false
            correctionCompositionSession.externalEditObserved()
            personalModelBacking = null
            observedTextSuffix.clear()
            suggestions = emptyList()
        }
        if (changes.typingProfileChanged) {
            typingIntelligenceBacking = null
            adaptiveProfileDirty = false
            adaptiveObservationsSinceSave = 0
            lastAdaptiveDecision = null
            pendingRejectedDecision = null
            clearCurrentWordTaps()
        }
    }

    private fun <Value> readIntelligenceContext(
        nullMeansUnavailable: Boolean = true,
        source: (InputConnection) -> Value?,
    ): Value? = EditorContextAccessGate.read(editorCapabilities.readContext) {
        val connection = currentInputConnection
        if (connection == null) {
            markEditorContextUnavailable()
            null
        } else {
            source(connection).also { value ->
                if (value == null && nullMeansUnavailable) markEditorContextUnavailable()
            }
        }
    }

    private fun readTextBeforeCursorForIntelligence(maximumCharacters: Int): String? =
        readIntelligenceContext { connection ->
            connection.getTextBeforeCursor(maximumCharacters, 0)?.toString()
        }

    private fun readTextAfterCursorForIntelligence(maximumCharacters: Int): String? =
        readIntelligenceContext { connection ->
            connection.getTextAfterCursor(maximumCharacters, 0)?.toString()
        }

    private fun readSelectedTextForIntelligence(): String? = readIntelligenceContext(
        nullMeansUnavailable = false,
    ) { connection ->
        connection.getSelectedText(0)?.toString()
    }

    private fun markEditorContextUnavailable() {
        if (!editorContextPrimitiveAvailable) return
        editorContextPrimitiveAvailable = false
        suggestions = emptyList()
        clearCurrentWordTaps()
        observedTextSuffix.clear()
        refreshEditorCapabilities()
    }

    private fun correctionEditor(
        connection: InputConnection,
        requiredContextSuffix: String? = null,
        renderReceipt: SuggestionRenderReceipt? = null,
    ) = InputConnectionCorrectionEditor(
        connection = connection,
        contextReader = ::readTextBeforeCursorForIntelligence,
        requiredContextSuffix = requiredContextSuffix,
        requiredExactContext = renderReceipt?.expectedContextBeforeCursor,
        exactContextMaximum = renderReceipt?.maximumContextLength ?: SUGGESTION_CONTEXT,
    )

    private fun correctionUndoEditor(
        connection: InputConnection,
        state: CorrectionUndoState,
    ) = CorrectionUndoEditor(
        connection = connection,
        state = state,
        beforeReader = ::readTextBeforeCursorForIntelligence,
        afterReader = ::readTextAfterCursorForIntelligence,
    )

    private fun adaptiveTypingPolicy(): TypingPolicy {
        if (secureField) return TypingPolicy.SENSITIVE
        if (!cachedSettings.adaptiveTypingEnabled || !editorCapabilities.suggestions.isAllowed) {
            return TypingPolicy.LITERAL
        }
        if (activePracticeSession != null) return TypingPolicy.PRACTICE
        return if (editorCapabilities.learning.isAllowed) {
            TypingPolicy.LEARNING
        } else {
            TypingPolicy.READ_ONLY
        }
    }

    private fun markAdaptiveProfileDirty() {
        adaptiveProfileDirty = true
        adaptiveObservationsSinceSave += 1
        if (adaptiveObservationsSinceSave >= ADAPTIVE_SAVE_INTERVAL) {
            persistAdaptiveProfile()
        }
    }

    private fun persistAdaptiveProfile(force: Boolean = false) {
        synchronizeLearningResetGenerations()
        if (!adaptiveProfileDirty || (!force && adaptiveObservationsSinceSave < ADAPTIVE_SAVE_INTERVAL)) {
            return
        }
        val saved = preferences.saveTypingProfile(
            profile = typingIntelligence.snapshot(),
            expectedResetGeneration = learningResetState.generations.typingProfile,
        )
        adaptiveProfileDirty = false
        adaptiveObservationsSinceSave = 0
        if (!saved) synchronizeLearningResetGenerations()
    }

    /**
     * Records the word being finished (before a space, return, or
     * punctuation) so predictions adapt to the user's vocabulary.
     */
    private fun learnCompletedWord() {
        if (!editorCapabilities.learning.isAllowed || activePracticeSession != null) return
        val before = readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT) ?: return
        val rawWord = WordTokenNormalizer.rawTrailingWord(before)
        if (
            SuggestionTargetBoundaryPolicy.proof(
                contextBeforeCursor = before,
                replaceBeforeCursor = rawWord.length,
                keyboardOwnedSuffix = keyboardOwnedCurrentWord(before),
            ) == null
        ) return
        val word = WordTokenNormalizer.canonicalize(rawWord)
        if (word.isEmpty()) return
        personalModel.learnCommittedText(
            word,
            before.dropLast(rawWord.length),
            currentLanguageTag,
        )
    }

    private fun learnCommittedText(
        text: String,
        contextBeforeText: String,
        languageTag: String = currentLanguageTag,
    ) {
        if (!editorCapabilities.learning.isAllowed || activePracticeSession != null) return
        personalModel.learnCommittedText(text, contextBeforeText, languageTag)
    }

    private fun removeWhitespaceBeforePunctuation(value: String): Int {
        val connection = currentInputConnection ?: return 0
        val before = readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT).orEmpty()
        val count = TextInsertionFormatter.whitespaceToDeleteBefore(before, value)
        return if (count > 0 && connection.deleteSurroundingText(count, 0)) count else 0
    }

    private fun sendCursorKeyEvents(
        connection: InputConnection,
        characterDelta: Int,
    ): Boolean {
        val keyCode = if (characterDelta < 0) {
            KeyEvent.KEYCODE_DPAD_LEFT
        } else {
            KeyEvent.KEYCODE_DPAD_RIGHT
        }
        var accepted = true
        repeat(abs(characterDelta)) {
            val down = connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            val up = connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
            accepted = accepted && down && up
        }
        return accepted
    }

    private fun sendWordDeleteKeyEvent(connection: InputConnection) {
        val eventTime = SystemClock.uptimeMillis()
        connection.sendKeyEvent(
            KeyEvent(
                eventTime,
                eventTime,
                KeyEvent.ACTION_DOWN,
                KeyEvent.KEYCODE_DEL,
                0,
                KeyEvent.META_CTRL_ON,
            ),
        )
        connection.sendKeyEvent(
            KeyEvent(
                eventTime,
                eventTime,
                KeyEvent.ACTION_UP,
                KeyEvent.KEYCODE_DEL,
                0,
                KeyEvent.META_CTRL_ON,
            ),
        )
    }

    private fun applyLocalWordCorrectionIfNeeded(): AppliedLocalCorrection? {
        if (!editorCapabilities.autoCorrection.isAllowed || activePracticeSession != null) return null
        if (!cachedSettings.automaticallyCorrectWords) return null
        val connection = currentInputConnection ?: return null
        val before = readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT) ?: return null
        val rawCurrentWord = WordTokenNormalizer.rawTrailingWord(before)
        val canonicalCurrentWord = WordTokenNormalizer.canonicalize(rawCurrentWord)
        if (canonicalCurrentWord.isEmpty()) return null
        if (
            SuggestionTargetBoundaryPolicy.proof(
                contextBeforeCursor = before,
                replaceBeforeCursor = rawCurrentWord.length,
                keyboardOwnedSuffix = keyboardOwnedCurrentWord(before),
            ) == null
        ) return null
        val precedingContext = before.dropLast(rawCurrentWord.length)
        val latticeReplacement = latticeCandidate(
            visibleWord = canonicalCurrentWord,
            precedingContext = precedingContext,
            policy = TapWordAcceptancePolicy.AUTOMATIC,
        )
        val replacement = latticeReplacement
            ?: SuggestionEngine.suggest(
                before,
                personalModel,
                currentLanguageTag,
                lexicon = keyboardLexicon,
            )
            .firstOrNull { it.kind == SuggestionKind.CORRECTION }
            ?.text
            ?: return null

        connection.beginBatchEdit()
        val didApply = try {
            val liveContext = readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT)
            if (liveContext != before) {
                false
            } else if (!connection.deleteSurroundingText(rawCurrentWord.length, 0)) {
                false
            } else if (connection.commitText(replacement, 1)) {
                true
            } else {
                connection.commitText(rawCurrentWord, 1)
                false
            }
        } finally {
            connection.endBatchEdit()
        }
        return if (didApply) {
            AppliedLocalCorrection(
                originalText = rawCurrentWord,
                replacementText = replacement,
                precedingContext = precedingContext,
                languageTag = currentLanguageTag,
                source = if (latticeReplacement != null) {
                    AutomaticSuggestionSource.TAP_LATTICE.receiptValue
                } else {
                    AutomaticSuggestionSource.SPELLING.receiptValue
                },
            )
        } else {
            null
        }
    }

    private fun recordLocalCorrection(
        correction: AppliedLocalCorrection?,
        boundaryText: String,
    ) {
        if (correction == null) return
        clearLocalCorrectionReceipt()
        val connection = currentInputConnection ?: run {
            learnAppliedCorrection(correction)
            return
        }
        val editor = correctionEditor(connection)
        val now = SystemClock.elapsedRealtime()
        val effect = correctionCompositionSession.recordAutomaticApplication(
            editor = editor,
            originalText = correction.originalText,
            replacementText = correction.replacementText,
            boundaryText = boundaryText,
            precedingContext = correction.precedingContext,
            languageTag = correction.languageTag,
            source = correction.source,
            atMilliseconds = now,
        )
        val hasReceipt = !effect.ignored && activateLocalCorrectionReceipt(now)
        if (!hasReceipt) learnAppliedCorrection(correction)
    }

    private fun activateLocalCorrectionReceipt(appliedAtMilliseconds: Long): Boolean {
        if (
            correctionCompositionSession.snapshot.receiptMode !=
            CorrectionCompositionReceiptMode.AUTOMATIC
        ) return false
        val receiptId = correctionCompositionSession.snapshot.receiptId ?: return false
        localCorrectionReceiptJob?.cancel()
        localCorrectionOriginalText = correctionCompositionSession.snapshot.originalText
        localCorrectionReceiptJob = scope.launch {
            delay(LOCAL_CORRECTION_RECEIPT_LIFETIME_MS)
            if (correctionCompositionSession.snapshot.receiptId == receiptId) {
                val activeConnection = currentInputConnection
                val expiry = if (activeConnection == null) {
                    correctionCompositionSession.externalEditObserved()
                    CorrectionCompositionEffect()
                } else {
                    correctionCompositionSession.advanceTime(
                        appliedAtMilliseconds + LOCAL_CORRECTION_RECEIPT_LIFETIME_MS,
                        correctionEditor(activeConnection),
                    )
                }
                if (
                    expiry.acceptedLearning != null &&
                    editorCapabilities.learning.isAllowed &&
                    activePracticeSession == null
                ) {
                    val learning = expiry.acceptedLearning
                    personalModel.learnCommittedText(
                        learning.text,
                        learning.precedingContext,
                        learning.languageTag,
                    )
                    personalModel.persist()
                }
                localCorrectionOriginalText = null
                localCorrectionReceiptJob = null
            }
        }
        return true
    }

    private fun learnAppliedCorrection(correction: AppliedLocalCorrection) {
        if (!editorCapabilities.learning.isAllowed || activePracticeSession != null) return
        personalModel.learnCommittedText(
            correction.replacementText,
            correction.precedingContext,
            correction.languageTag,
        )
        personalModel.persist()
    }

    fun revertLocalCorrection(
        mode: LocalCorrectionRevertMode = LocalCorrectionRevertMode.VISIBLE_UNDO,
    ): Boolean {
        if (
            correctionCompositionSession.snapshot.receiptMode !=
            CorrectionCompositionReceiptMode.AUTOMATIC
        ) return false
        val connection = currentInputConnection ?: run {
            clearLocalCorrectionReceipt()
            return false
        }
        val originalText = correctionCompositionSession.snapshot.originalText.orEmpty()
        val editor = correctionEditor(connection)
        val effect = when (mode) {
            LocalCorrectionRevertMode.BACKSPACE ->
                correctionCompositionSession.backspace(editor)
            LocalCorrectionRevertMode.VISIBLE_UNDO ->
                correctionCompositionSession.visibleRevert(editor)
        }
        localCorrectionReceiptJob?.cancel()
        localCorrectionReceiptJob = null
        localCorrectionOriginalText = null
        if (!effect.didMutateEditor) return false
        clearCorrectionUndo()
        cancelCorrection()
        observedTextSuffix.clear()
        effect.rejection?.let { rejection ->
            if (editorCapabilities.learning.isAllowed) {
                recordAutomaticCorrectionRejection(personalModel, rejection)
            }
            observeCommittedText(rejection.restoredText)
        }
        setStatus(
            "Restored “$originalText”.",
        )
        refreshTypingState()
        return true
    }

    private fun clearLocalCorrectionReceipt(acceptLearning: Boolean = false) {
        localCorrectionReceiptJob?.cancel()
        localCorrectionReceiptJob = null
        localCorrectionOriginalText = null
        if (
            correctionCompositionSession.snapshot.receiptMode ==
            CorrectionCompositionReceiptMode.AUTOMATIC
        ) {
            val connection = currentInputConnection
            if (connection == null) {
                correctionCompositionSession.externalEditObserved()
            } else {
                val effect = correctionCompositionSession.finishActiveReceipt(
                    correctionEditor(connection),
                    acceptLearning = acceptLearning,
                )
                if (
                    effect.acceptedLearning != null &&
                    editorCapabilities.learning.isAllowed &&
                    activePracticeSession == null
                ) {
                    val learning = effect.acceptedLearning
                    personalModel.learnCommittedText(
                        learning.text,
                        learning.precedingContext,
                        learning.languageTag,
                    )
                    personalModel.persist()
                }
            }
        }
    }

    private fun consumeObservedFinalWord(): Boolean {
        val before = readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT) ?: return false
        return observedTextSuffix.consumeIfUnchanged(before)
    }

    private fun commitObservedText(
        text: String,
        languageTag: String = currentLanguageTag,
    ): Boolean {
        if (text.isBlank()) return false
        val connection = currentInputConnection ?: return false
        val before = readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT)
        val plan = TextInsertionFormatter.planInsertion(text, before)
        if (plan.text.isBlank()) return false
        val removedText = before?.takeLast(plan.deleteBeforeCursor).orEmpty()

        connection.beginBatchEdit()
        val didCommit = try {
            if (
                plan.deleteBeforeCursor > 0 &&
                !connection.deleteSurroundingText(plan.deleteBeforeCursor, 0)
            ) {
                false
            } else if (connection.commitText(plan.text, 1)) {
                true
            } else {
                if (removedText.isNotEmpty()) connection.commitText(removedText, 1)
                false
            }
        } finally {
            connection.endBatchEdit()
        }
        if (didCommit) {
            if (before != null) {
                learnCommittedText(text, before.dropLast(plan.deleteBeforeCursor), languageTag)
            }
            observeCommittedText(plan.text)
        }
        return didCommit
    }

    private fun observeCommittedText(text: String) {
        val before = readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT) ?: run {
            observedTextSuffix.clear()
            return
        }
        observedTextSuffix.observe(text, before)
    }

    private fun cancelCorrection() {
        correctionRequestOwnership.cancel()
        val job = correctionJob
        correctionJob = null
        isCorrecting = false
        job?.cancel()
    }

    private fun clearReviewProposal() {
        reviewProposal = null
        pendingReviewSnapshot = null
    }

    private fun beginCorrectionUndo(
        state: CorrectionUndoState,
        durationSeconds: Int,
        learning: PendingCorrectionLearning,
    ) {
        clearCorrectionUndo()
        val connection = currentInputConnection ?: return
        val durationMilliseconds = durationSeconds.coerceIn(1, 10) * 1_000L
        val effect = correctionCompositionSession.recordExplicitApplication(
            editor = correctionUndoEditor(connection, state),
            originalText = state.originalText,
            replacementText = state.replacementText,
            source = "buddyFix",
            precedingContext = learning.precedingContext,
            languageTag = learning.languageTag,
            atMilliseconds = SystemClock.elapsedRealtime(),
            receiptLifetimeMilliseconds = durationMilliseconds,
        )
        if (effect.ignored) return
        pendingCorrectionUndo = state
        pendingCorrectionLearning = learning
        canUndoCorrection = true
        correctionUndoJob = scope.launch {
            delay(durationMilliseconds)
            clearCorrectionUndo()
        }
    }

    private fun clearCorrectionUndo(acceptLearning: Boolean = true) {
        correctionUndoJob?.cancel()
        correctionUndoJob = null
        val undo = pendingCorrectionUndo
        val acceptance = if (
            correctionCompositionSession.snapshot.receiptMode ==
            CorrectionCompositionReceiptMode.EXPLICIT && undo != null
        ) {
            val connection = currentInputConnection
            if (connection == null) {
                correctionCompositionSession.externalEditObserved()
                CorrectionCompositionEffect()
            } else {
                correctionCompositionSession.finishActiveReceipt(
                    correctionUndoEditor(connection, undo),
                    acceptLearning,
                )
            }
        } else {
            CorrectionCompositionEffect()
        }
        if (
            acceptLearning &&
            acceptance.acceptedLearning != null &&
            activePracticeSession == null &&
            editorCapabilities.learning.isAllowed
        ) {
            pendingCorrectionLearning?.let { learning ->
                personalModel.learnCommittedText(
                    learning.text,
                    learning.precedingContext,
                    learning.languageTag,
                )
            }
        }
        pendingCorrectionUndo = null
        pendingCorrectionLearning = null
        canUndoCorrection = false
    }

    private fun correctionUndoStillMatches(
        undo: CorrectionUndoState? = pendingCorrectionUndo,
    ): Boolean {
        if (!editorCapabilities.readContext.isAllowed) return false
        val state = undo ?: return false
        val before = readTextBeforeCursorForIntelligence(
            state.anchorBefore.length + state.replacementText.length,
        ).orEmpty()
        val after = readTextAfterCursorForIntelligence(state.anchorAfter.length).orEmpty()
        return state.matches(before, after)
    }

    private fun refreshTypingState() {
        typingRefreshJob?.cancel()
        typingRefreshJob = null
        performTypingStateRefresh()
    }

    /**
     * Prediction work is intentionally outside the editor commit critical
     * section. Rapid taps cancel stale work and pay for one fresh context read
     * after the short burst instead of one read and full dictionary pass per key.
     */
    private fun scheduleTypingStateRefresh() {
        typingRefreshJob?.cancel()
        typingRefreshJob = scope.launch {
            delay(TYPING_REFRESH_DELAY_MS)
            typingRefreshJob = null
            performTypingStateRefresh()
        }
    }

    private fun performTypingStateRefresh() {
        val refreshPlan = KeyboardRefreshPolicy.plan(
            suggestionsAllowed = editorCapabilities.suggestions.isAllowed,
            readContextAllowed = editorCapabilities.readContext.isAllowed,
            practiceActive = activePracticeSession != null,
        )
        if (!refreshPlan.shouldReadContext) {
            suggestions = emptyList()
            observedTextSuffix.clear()
            if (refreshPlan.shouldUseCursorCapsMode(contextReadSucceeded = false)) {
                refreshAutoShiftFromCursorCapsMode()
            }
            return
        }
        val before = readTextBeforeCursorForIntelligence(SUGGESTION_CONTEXT) ?: run {
            suggestions = emptyList()
            observedTextSuffix.clear()
            if (refreshPlan.shouldUseCursorCapsMode(contextReadSucceeded = false)) {
                refreshAutoShiftFromCursorCapsMode()
            }
            return
        }
        val currentWordLength = before
            .takeLastWhile(WordTokenNormalizer::isWordCharacter)
            .let { TapWordDecoder.expectedTapCount(it) ?: 0 }
        if (currentWordTaps.size != currentWordLength) clearCurrentWordTaps()
        keyboardState.updateAutoShift(before, capitalizationMode)
        if (!refreshPlan.shouldShowSuggestions) {
            suggestions = emptyList()
            observedTextSuffix.clear()
            return
        }
        observedTextSuffix.retainIfUnchanged(before)
        val baseline = SuggestionEngine.suggest(
            before,
            personalModel,
            currentLanguageTag,
            suggestionsAllowed = editorCapabilities.suggestions.isAllowed,
            lexicon = keyboardLexicon,
        )
        val lattice = latticeSuggestion(before)
        val keyboardOwnedWord = keyboardOwnedCurrentWord(before)
        suggestions = (listOfNotNull(lattice) + baseline)
            .mapNotNull { suggestion ->
                renderSuggestion(
                    suggestion = suggestion,
                    contextBeforeCursor = before,
                    keyboardOwnedSuffix = keyboardOwnedWord,
                )
            }
            .distinctBy { it.text.lowercase(Locale.ROOT) }
            .take(SuggestionEngine.MAX_SUGGESTIONS)
    }

    private fun refreshAutoShiftFromCursorCapsMode() {
        val cursorCapsMode = runCatching {
            currentInputConnection?.getCursorCapsMode(
                capitalizationMode.cursorCapsModeRequest,
            )
        }.getOrNull()
        keyboardState.updateAutoShiftFromCursorCapsMode(cursorCapsMode)
    }

    /** Binds a visible row to one field/language and one exact bounded editor observation. */
    private fun renderSuggestion(
        suggestion: Suggestion,
        contextBeforeCursor: String,
        keyboardOwnedSuffix: String? = null,
    ): Suggestion? {
        val ownedSuggestion = suggestion.automaticReplacement?.let { replacement ->
            suggestion.copy(
                automaticReplacement = replacement.ownedBy(
                    fieldEpoch = fieldEpoch,
                    fieldIdentifier = fieldIdentifier,
                    languageTag = currentLanguageTag,
                ),
            )
        } ?: suggestion
        val receipt = SuggestionRenderReceipt.capture(
            suggestion = ownedSuggestion,
            contextBeforeCursor = contextBeforeCursor,
            maximumContextLength = SUGGESTION_CONTEXT,
            fieldEpoch = fieldEpoch,
            fieldIdentifier = fieldIdentifier,
            languageTag = currentLanguageTag,
            keyboardOwnedSuffix = keyboardOwnedSuffix,
        ) ?: return null
        return ownedSuggestion.copy(renderReceipt = receipt)
    }

    /** Current ASCII tap composition is an explicit proof even at a truncated window edge. */
    private fun keyboardOwnedCurrentWord(contextBeforeCursor: String): String? {
        val rawWord = WordTokenNormalizer.rawTrailingWord(contextBeforeCursor)
        if (rawWord.isEmpty() || rawWord.length != currentWordTaps.size) return null
        val committedPath = currentWordTaps.joinToString(separator = "") { tap ->
            tap.resolvedKey.toString()
        }
        return rawWord.takeIf {
            KeyboardOwnedWordProvenancePolicy.ownsCurrentWord(
                rawCurrentWord = rawWord,
                resolvedTapPath = committedPath,
                startedAtProvenBoundary = currentWordStartedAtProvenBoundary,
            )
        }
    }

    private fun latticeSuggestion(before: String): Suggestion? {
        val rawVisibleWord = WordTokenNormalizer.rawTrailingWord(before)
        val canonicalVisibleWord = WordTokenNormalizer.canonicalize(rawVisibleWord)
        if (canonicalVisibleWord.isEmpty()) return null
        val candidate = latticeCandidate(
            visibleWord = canonicalVisibleWord,
            precedingContext = before.dropLast(rawVisibleWord.length),
            policy = TapWordAcceptancePolicy.SUGGESTION,
        ) ?: return null
        val automaticReplacement = AutomaticSuggestionReplacement.create(
            originalText = rawVisibleWord,
            replacementText = candidate,
            boundaryText = " ",
            precedingContext = before.dropLast(rawVisibleWord.length),
            source = AutomaticSuggestionSource.TAP_LATTICE,
        )?.ownedBy(fieldEpoch, fieldIdentifier, currentLanguageTag) ?: return null
        return Suggestion(
            text = candidate,
            replaceBeforeCursor = rawVisibleWord.length,
            appendSpace = true,
            kind = SuggestionKind.CORRECTION,
            automaticReplacement = automaticReplacement,
        )
    }

    private fun latticeCandidate(
        visibleWord: String,
        precedingContext: String,
        policy: TapWordAcceptancePolicy,
    ): String? {
        if (
            personalModel.usageCount(visibleWord, currentLanguageTag) >=
            SuggestionEngine.PERSONAL_USAGE_CORRECTION_PROTECTION_THRESHOLD
        ) return null
        if (currentWordTaps.size != TapWordDecoder.expectedTapCount(visibleWord)) return null
        val previousWord = precedingContext
            .trimEnd()
            .takeLastWhile(WordTokenNormalizer::isWordCharacter)
            .let(WordTokenNormalizer::canonicalize)
            .takeIf(String::isNotEmpty)
        val result = tapWordDecoder.decode(
            taps = currentWordTaps,
            previousWord = previousWord,
            languageTag = currentLanguageTag,
            limit = 5,
        )
        val replacement = policy.acceptedReplacement(
            result = result,
            visibleWord = visibleWord,
            isSuppressed = { typed, suggestion ->
                personalModel.isCorrectionSuppressed(
                    typed = typed,
                    suggestion = suggestion,
                    languageTag = currentLanguageTag,
                )
            },
        ) ?: return null
        return matchingCapitalization(replacement, visibleWord)
    }

    private fun matchingCapitalization(candidate: String, source: String): String = when {
        source.any(Char::isLetter) && source.all { !it.isLetter() || it.isUpperCase() } ->
            candidate.uppercase(Locale.ROOT)
        source.firstOrNull()?.isUpperCase() == true ->
            candidate.lowercase(Locale.ROOT).replaceFirstChar { it.uppercaseChar() }
        else -> candidate.lowercase(Locale.ROOT)
    }

    private fun expectedPracticeCharacter(responseLength: Int): Char? = activePracticeSession
        ?.expectedText
        ?.getOrNull(responseLength)
        ?.lowercaseChar()
        ?.takeIf(Char::isLetter)

    private fun showBaselineStatus() {
        val catalogWarning = catalogLoadWarning
        if (catalogWarning != null) {
            setStatus(catalogWarning, error = true, transient = false)
        } else if (!editorCapabilities.suggestions.isAllowed) {
            setStatus(
                editorCapabilities.suggestions.denialMessage("Suggestions"),
                transient = false,
            )
        } else if (!editorCapabilities.readContext.isAllowed) {
            setStatus(
                editorCapabilities.readContext.denialMessage("Suggestions"),
                transient = false,
            )
        } else {
            clearStatus()
        }
    }

    private fun setStatus(message: String, error: Boolean = false, transient: Boolean = true) {
        statusClearJob?.cancel()
        status = KeyboardStatus(message, error)
        if (transient) {
            statusClearJob = scope.launch {
                delay(STATUS_LIFETIME_MS)
                status = null
            }
        }
    }

    private fun clearStatus() {
        statusClearJob?.cancel()
        statusClearJob = null
        status = null
    }

    private fun resolveReturnAction(info: EditorInfo?): Int {
        val options = info?.imeOptions ?: return returnActionFor(keyboardPresentation.returnIntent)
        if (options and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0) return EditorInfo.IME_ACTION_NONE
        val editorAction = options and EditorInfo.IME_MASK_ACTION
        return if (
            editorAction == EditorInfo.IME_ACTION_NONE ||
            editorAction == EditorInfo.IME_ACTION_UNSPECIFIED
        ) {
            returnActionFor(keyboardPresentation.returnIntent)
        } else {
            editorAction
        }
    }

    private fun returnActionFor(intent: ReturnIntent): Int = when (intent) {
        ReturnIntent.NEWLINE -> EditorInfo.IME_ACTION_NONE
        ReturnIntent.DONE -> EditorInfo.IME_ACTION_DONE
        ReturnIntent.GO -> EditorInfo.IME_ACTION_GO
        ReturnIntent.NEXT -> EditorInfo.IME_ACTION_NEXT
        ReturnIntent.SEARCH -> EditorInfo.IME_ACTION_SEARCH
        ReturnIntent.SEND -> EditorInfo.IME_ACTION_SEND
    }

    private fun refreshEditorCapabilities(info: EditorInfo? = currentInputEditorInfo) {
        if (info != null) cachedSettings = preferences.loadSettings()
        editorCapabilities = if (info == null) {
            EditorCapabilities.INACTIVE
        } else {
            EditorCapabilityPolicy.evaluateAndroid(
                inputType = info.inputType,
                imeOptions = info.imeOptions,
                privateImeOptions = info.privateImeOptions,
                cloudConsentGranted = cachedSettings.hasAcceptedCloudProcessing,
                platformVoiceAvailable = SpeechRecognizer.isRecognitionAvailable(this),
                editorCanMoveCursor = editorCursorPrimitiveAvailable,
                sharedTranscriptAvailable = preferences.loadPendingTranscript() != null,
                editorCanReadContext = editorContextPrimitiveAvailable,
                // This IME uses direct atomic replacement and does not create
                // native composing spans.
                editorCanUseComposition = false,
            )
        }
        keyboardPresentation = KeyboardCatalog.presentation(
            fieldKind = editorCapabilities.presentationFieldKind.catalogFieldKind,
            localeIdentifier = currentLanguageTag,
        )
    }

    private fun resolveLanguageTag(
        info: EditorInfo?,
        subtype: InputMethodSubtype? = getSystemService(InputMethodManager::class.java)
            .currentInputMethodSubtype,
    ): String {
        val subtypeTags = listOfNotNull(
            subtype?.languageTag?.takeIf(String::isNotBlank),
        ).distinct()
        val hintedLocales = info?.hintLocales
        val hintedTags = if (hintedLocales == null) {
            emptyList()
        } else {
            (0 until hintedLocales.size()).map { hintedLocales[it].toLanguageTag() }
        }
        val deviceLocales = resources.configuration.locales
        val deviceTags = (0 until deviceLocales.size())
            .map { deviceLocales[it].toLanguageTag() }
            .ifEmpty { listOf(Locale.getDefault().toLanguageTag()) }
        return LanguageSupport.preferredTag(subtypeTags + hintedTags, deviceTags)
    }

    private data class CorrectionSnapshot(
        val fieldEpoch: Long,
        val languageTag: String,
        val target: CorrectionTarget,
        val candidate: TextCorrectionCandidate,
        val textBeforeCursor: String,
        val textAfterCursor: String,
        val anchorBefore: String,
        val anchorAfter: String,
    )

    private data class PendingCorrectionLearning(
        val text: String,
        val precedingContext: String,
        val languageTag: String,
    )

    private data class AppliedLocalCorrection(
        val originalText: String,
        val replacementText: String,
        val precedingContext: String,
        val languageTag: String,
        val source: String,
    )

    private data class AdaptiveDecision(
        val tap: TapPoint,
        val policy: TypingPolicy,
        val createdAtMillis: Long,
    )

    private enum class CorrectionTarget { Selection, CurrentSentence }

    private companion object {
        const val LOG_TAG = "BuddyGrammarIME"
        const val CATALOG_FALLBACK_WARNING =
            "Keyboard layout data could not be loaded. Safe defaults are active."
        const val MAX_CONTEXT = 1_000
        const val CORRECTION_CONTEXT_READ_LIMIT = MAX_CONTEXT + 128
        const val ANCHOR_LENGTH = 64
        const val SUGGESTION_CONTEXT = 64
        const val TYPING_REFRESH_DELAY_MS = 24L
        const val MAX_WORD_DELETE_CONTEXT = 256
        const val GRAPHEME_CONTEXT_UTF16 = 256
        const val STATUS_LIFETIME_MS = 4_000L
        const val LOCAL_CORRECTION_RECEIPT_LIFETIME_MS = 3_000L
        const val RETYPE_WINDOW_MS = 3_000L
        const val ADAPTIVE_SAVE_INTERVAL = 8
        val WORD_BOUNDARY_PUNCTUATION = setOf('.', ',', '?', '!', ';', ':')
    }
}
