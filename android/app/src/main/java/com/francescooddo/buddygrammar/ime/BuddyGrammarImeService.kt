package com.francescooddo.buddygrammar.ime

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
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
import com.francescooddo.buddygrammar.core.BuddyGrammarApi
import com.francescooddo.buddygrammar.core.CorrectionUndoState
import com.francescooddo.buddygrammar.core.HandwritingTextFormatter
import com.francescooddo.buddygrammar.core.LanguageSupport
import com.francescooddo.buddygrammar.core.ObservedTextSuffix
import com.francescooddo.buddygrammar.core.PersonalLanguageModel
import com.francescooddo.buddygrammar.core.PreferencesRepository
import com.francescooddo.buddygrammar.core.Suggestion
import com.francescooddo.buddygrammar.core.SuggestionEngine
import com.francescooddo.buddygrammar.core.SuggestionKind
import com.francescooddo.buddygrammar.core.TextCorrectionCandidate
import com.francescooddo.buddygrammar.core.TextContextExtractor
import com.francescooddo.buddygrammar.core.TextInsertionFormatter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

data class KeyboardStatus(val message: String, val isError: Boolean = false)

class BuddyGrammarImeService :
    InputMethodService(),
    LifecycleOwner,
    ViewModelStoreOwner,
    SavedStateRegistryOwner {

    private val preferences by lazy { PreferencesRepository(this) }
    private val personalModel by lazy {
        val store = getSharedPreferences(PERSONAL_MODEL_PREFS, MODE_PRIVATE)
        PersonalLanguageModel(
            initialData = store.getString(PERSONAL_MODEL_KEY, null),
            onPersist = { data -> store.edit().putString(PERSONAL_MODEL_KEY, data).apply() },
        )
    }
    private val api = BuddyGrammarApi()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val lifecycleRegistry = LifecycleRegistry(this)
    private val store = ViewModelStore()
    private val savedStateRegistryController = SavedStateRegistryController.create(this)

    override val lifecycle: Lifecycle get() = lifecycleRegistry
    override val viewModelStore: ViewModelStore get() = store
    override val savedStateRegistry: SavedStateRegistry
        get() = savedStateRegistryController.savedStateRegistry

    val keyboardState = KeyboardState()
    val handwriting by lazy { HandwritingController(scope) { currentLanguageTag } }
    val voice by lazy {
        VoiceTypingController(
            context = this,
            onFinalText = { finalText -> commitDictatedText(finalText) },
            languageTagProvider = { currentLanguageTag },
        )
    }

    var suggestions by mutableStateOf<List<Suggestion>>(emptyList())
        private set
    var status by mutableStateOf<KeyboardStatus?>(null)
        private set
    var secureField by mutableStateOf(false)
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
    private var correctionUndoJob: Job? = null
    private var pendingCorrectionUndo: CorrectionUndoState? = null
    private var pendingCorrectionLearning: PendingCorrectionLearning? = null
    private var statusClearJob: Job? = null
    private var allowsDictionarySuggestions = false
    private var allowsPersonalizedLearning = false
    private var currentLanguageTag = LanguageSupport.DEFAULT_LANGUAGE_TAG
    private val observedTextSuffix = ObservedTextSuffix(SUGGESTION_CONTEXT)

    override fun onCreate() {
        super.onCreate()
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

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        secureField = info?.inputType?.let(::isSecureInputType) ?: false
        currentLanguageTag = resolveLanguageTag(info)
        allowsDictionarySuggestions = info?.inputType
            ?.let(EditorSuggestionPolicy::allowsDictionarySuggestions)
            ?: false
        allowsPersonalizedLearning = info != null && !secureField &&
            info.imeOptions.and(EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING) == 0
        observedTextSuffix.clear()
        val inputClass = info?.inputType?.and(InputType.TYPE_MASK_CLASS)
        val startOnNumbers = inputClass == InputType.TYPE_CLASS_NUMBER ||
            inputClass == InputType.TYPE_CLASS_PHONE ||
            inputClass == InputType.TYPE_CLASS_DATETIME
        keyboardState.configureForNewInput(startOnNumbers)
        returnAction = resolveReturnAction(info)
        hasMicPermission = hasMicrophonePermission()
        clearCorrectionUndo()
        cancelCorrection()
        showBaselineStatus()
        refreshTypingState()
    }

    override fun onWindowShown() {
        super.onWindowShown()
        hasMicPermission = hasMicrophonePermission()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        personalModel.persist()
        clearCorrectionUndo()
        cancelCorrection()
        observedTextSuffix.clear()
        voice.destroy()
        handwriting.clear()
        super.onFinishInputView(finishingInput)
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
        if (canUndoCorrection && !correctionUndoStillMatches()) {
            clearCorrectionUndo()
        }
        refreshTypingState()
    }

    override fun onDestroy() {
        voice.destroy()
        handwriting.destroy()
        clearCorrectionUndo()
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_STOP)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        store.clear()
        scope.cancel()
        super.onDestroy()
    }

    // region Key handling

    fun onCharacterKey(value: String) {
        val finishesWord = value.length == 1 && value[0] in WORD_BOUNDARY_PUNCTUATION
        localEdit(preserveObservedSuffix = finishesWord)
        if (finishesWord) {
            val removedWhitespace = removeWhitespaceBeforePunctuation(value)
            val alreadyProcessed = if (removedWhitespace > 0) {
                observedTextSuffix.clear()
                true
            } else {
                consumeObservedFinalWord()
            }
            if (!alreadyProcessed) {
                applyLocalWordCorrectionIfNeeded()
                learnCompletedWord()
            }
        }
        val text = if (keyboardState.layer == KeyboardLayer.LETTERS && keyboardState.uppercase) {
            value.uppercase()
        } else {
            value
        }
        currentInputConnection?.commitText(text, 1)
        keyboardState.onCharacterCommitted()
        refreshTypingState()
    }

    fun onSpaceKey() {
        localEdit(preserveObservedSuffix = true)
        if (!consumeObservedFinalWord()) {
            applyLocalWordCorrectionIfNeeded()
            learnCompletedWord()
        }
        currentInputConnection?.commitText(" ", 1)
        refreshTypingState()
    }

    fun onDeleteKey() {
        localEdit()
        val connection = currentInputConnection ?: return
        if (!connection.deleteSurroundingTextInCodePoints(1, 0)) {
            connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
            connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
        }
        refreshTypingState()
    }

    fun onReturnKey() {
        localEdit(preserveObservedSuffix = true)
        if (!consumeObservedFinalWord()) {
            applyLocalWordCorrectionIfNeeded()
            learnCompletedWord()
        }
        val action = currentInputEditorInfo?.imeOptions?.and(EditorInfo.IME_MASK_ACTION)
        val handledAction = action != null && action != EditorInfo.IME_ACTION_NONE &&
            action != EditorInfo.IME_ACTION_UNSPECIFIED &&
            currentInputConnection?.performEditorAction(action) == true
        if (!handledAction) currentInputConnection?.commitText("\n", 1)
        refreshTypingState()
    }

    fun onShiftKey() {
        keyboardState.onShiftTapped()
    }

    fun setLayer(layer: KeyboardLayer) {
        if (keyboardState.layer == KeyboardLayer.VOICE && layer != KeyboardLayer.VOICE) {
            voice.destroy()
        }
        keyboardState.switchLayer(layer)
        when (layer) {
            KeyboardLayer.HANDWRITING -> handwriting.prepareModel()
            KeyboardLayer.LETTERS -> refreshTypingState()
            else -> Unit
        }
    }

    fun switchKeyboard() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && shouldOfferSwitchingToNextInputMethod()) {
            switchToNextInputMethod(false)
        } else {
            getSystemService(InputMethodManager::class.java).showInputMethodPicker()
        }
    }

    fun applySuggestion(suggestion: Suggestion) {
        localEdit()
        val connection = currentInputConnection ?: return
        val before = connection.getTextBeforeCursor(SUGGESTION_CONTEXT, 0)?.toString().orEmpty()
        val replaceCount = suggestion.replaceBeforeCursor.coerceAtMost(before.length)
        val original = before.takeLast(replaceCount)
        val prefix = before.dropLast(replaceCount)
        connection.beginBatchEdit()
        val didApply = try {
            if (replaceCount > 0 && !connection.deleteSurroundingText(replaceCount, 0)) {
                false
            } else if (
                connection.commitText(
                    suggestion.text + if (suggestion.appendSpace) " " else "",
                    1,
                )
            ) {
                true
            } else {
                if (replaceCount > 0) connection.commitText(original, 1)
                false
            }
        } finally {
            connection.endBatchEdit()
        }
        if (didApply && !suggestion.isEmoji && allowsPersonalizedLearning) {
            personalModel.learnCommittedText(
                suggestion.text.trim(),
                prefix,
                currentLanguageTag,
            )
        }
        refreshTypingState()
    }

    fun commitEmoji(emoji: String) {
        localEdit()
        currentInputConnection?.commitText(emoji, 1)
        refreshTypingState()
    }

    fun commitHandwriting(text: String) {
        localEdit(preserveObservedSuffix = true)
        val connection = currentInputConnection ?: return
        val before = connection.getTextBeforeCursor(SUGGESTION_CONTEXT, 0)?.toString().orEmpty()
        val formatted = HandwritingTextFormatter.textForInsertion(text, before, currentLanguageTag)
        commitObservedText(formatted)
        handwriting.clear()
        refreshTypingState()
    }

    private fun commitDictatedText(text: String) {
        if (secureField) return
        localEdit(preserveObservedSuffix = true)
        commitObservedText(text.trim())
        refreshTypingState()
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

    // region Cloud correction (unchanged flow)

    fun correctCurrentText() {
        clearCorrectionUndo()
        cancelCorrection()
        if (secureField) {
            setStatus("Cloud actions are unavailable in secure fields.", error = true)
            return
        }
        val settings = preferences.loadSettings()
        if (!settings.hasAcceptedCloudProcessing) {
            setStatus("Allow cloud processing in BuddyGrammar to use ★.", error = true)
            return
        }
        val snapshot = captureSnapshot()
        if (snapshot == null) {
            setStatus("Type some text first.", error = true)
            return
        }

        setStatus("Correcting…", transient = false)
        isCorrecting = true
        correctionJob = scope.launch {
            try {
                val corrected = api.correct(
                    text = snapshot.candidate.requestText,
                    clientId = preferences.installationId(),
                    modelId = settings.activeModelId,
                    instruction = settings.correctionInstruction,
                )
                val replacement = snapshot.candidate.replacement(corrected)
                val didApply = applyCorrection(snapshot, replacement)
                if (didApply) {
                    observeCommittedText(replacement)
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
                            languageTag = currentLanguageTag,
                        ),
                    )
                }
                setStatus(
                    if (didApply) {
                        "Correction applied."
                    } else {
                        "The text changed, so the correction was not applied."
                    },
                    error = !didApply,
                )
            } catch (_: CancellationException) {
                // Editing intentionally cancels an obsolete correction request.
            } catch (error: Throwable) {
                setStatus(error.message ?: "Correction failed.", error = true)
            } finally {
                isCorrecting = false
                correctionJob = null
            }
        }
    }

    private fun captureSnapshot(): CorrectionSnapshot? {
        val connection = currentInputConnection ?: return null
        val selected = connection.getSelectedText(0)?.toString().orEmpty()
        TextCorrectionCandidate.from(selected)?.let { candidate ->
            return CorrectionSnapshot(
                target = CorrectionTarget.Selection,
                candidate = candidate,
                textBeforeCursor = "",
                textAfterCursor = "",
                anchorBefore = connection.getTextBeforeCursor(ANCHOR_LENGTH, 0)?.toString().orEmpty(),
                anchorAfter = connection.getTextAfterCursor(ANCHOR_LENGTH, 0)?.toString().orEmpty(),
            )
        }
        val before = connection.getTextBeforeCursor(MAX_CONTEXT, 0)
            ?.toString().orEmpty()
        val after = connection.getTextAfterCursor(MAX_CONTEXT, 0)
            ?.toString().orEmpty()
        val cursorCandidate = TextContextExtractor.currentSentence(before, after) ?: return null
        return CorrectionSnapshot(
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
        val connection = currentInputConnection ?: return false
        return when (snapshot.target) {
            CorrectionTarget.Selection -> {
                connection.getSelectedText(0)?.toString() == snapshot.candidate.capturedText &&
                    connection.getTextBeforeCursor(ANCHOR_LENGTH, 0)?.toString() == snapshot.anchorBefore &&
                    connection.getTextAfterCursor(ANCHOR_LENGTH, 0)?.toString() == snapshot.anchorAfter
            }
            CorrectionTarget.CurrentSentence -> {
                val expectedBefore = snapshot.anchorBefore + snapshot.textBeforeCursor
                val expectedAfter = snapshot.textAfterCursor + snapshot.anchorAfter
                connection.getTextBeforeCursor(expectedBefore.length, 0)?.toString() == expectedBefore &&
                    connection.getTextAfterCursor(expectedAfter.length, 0)?.toString() == expectedAfter
            }
        }
    }

    fun undoLastCorrection() {
        val undo = pendingCorrectionUndo ?: return
        clearCorrectionUndo(acceptLearning = false)
        val connection = currentInputConnection
        if (connection == null || !correctionUndoStillMatches(undo)) {
            setStatus("The text changed, so the correction could not be undone.", error = true)
            return
        }

        connection.beginBatchEdit()
        val didUndo = try {
            if (!connection.deleteSurroundingText(undo.replacementText.length, 0)) {
                false
            } else if (connection.commitText(undo.originalText, 1)) {
                true
            } else {
                connection.commitText(undo.replacementText, 1)
                false
            }
        } finally {
            connection.endBatchEdit()
        }
        observedTextSuffix.clear()
        setStatus(
            if (didUndo) "Correction undone." else "The editor rejected Undo.",
            error = !didUndo,
        )
        refreshTypingState()
    }

    fun insertPendingTranscript() {
        localEdit(preserveObservedSuffix = true)
        if (secureField) {
            setStatus("Dictation is unavailable in secure fields.", error = true)
            return
        }
        if (!preferences.loadSettings().hasAcceptedCloudProcessing) {
            setStatus("Allow cloud processing in BuddyGrammar first.", error = true)
            return
        }
        val transcript = preferences.loadPendingTranscript()
        if (transcript == null) {
            setStatus("No dictation is waiting. Record one in BuddyGrammar first.", error = true)
            return
        }
        if (commitObservedText(transcript.text, transcript.languageCode ?: currentLanguageTag)) {
            preferences.clearPendingTranscript()
            setStatus("Dictation inserted.")
        } else {
            setStatus("The editor rejected the dictation. It is still saved.", error = true)
        }
        refreshTypingState()
    }

    // endregion

    private fun localEdit(preserveObservedSuffix: Boolean = false) {
        clearCorrectionUndo()
        cancelCorrection()
        if (!preserveObservedSuffix) observedTextSuffix.clear()
        showBaselineStatus()
    }

    /**
     * Records the word being finished (before a space, return, or
     * punctuation) so predictions adapt to the user's vocabulary.
     */
    private fun learnCompletedWord() {
        if (!allowsPersonalizedLearning) return
        val before = currentInputConnection
            ?.getTextBeforeCursor(SUGGESTION_CONTEXT, 0)
            ?.toString()
            .orEmpty()
        val word = before.takeLastWhile { it.isLetterOrDigit() || it == '\'' }
        if (word.isEmpty()) return
        personalModel.learnCommittedText(
            word,
            before.dropLast(word.length),
            currentLanguageTag,
        )
    }

    private fun learnCommittedText(
        text: String,
        contextBeforeText: String,
        languageTag: String = currentLanguageTag,
    ) {
        if (!allowsPersonalizedLearning) return
        personalModel.learnCommittedText(text, contextBeforeText, languageTag)
    }

    private fun removeWhitespaceBeforePunctuation(value: String): Int {
        val connection = currentInputConnection ?: return 0
        val before = connection.getTextBeforeCursor(SUGGESTION_CONTEXT, 0)?.toString().orEmpty()
        val count = TextInsertionFormatter.whitespaceToDeleteBefore(before, value)
        return if (count > 0 && connection.deleteSurroundingText(count, 0)) count else 0
    }

    private fun applyLocalWordCorrectionIfNeeded(): Boolean {
        if (secureField || !allowsDictionarySuggestions) return false
        if (!preferences.loadSettings().automaticallyCorrectWords) return false
        val connection = currentInputConnection ?: return false
        val before = connection.getTextBeforeCursor(SUGGESTION_CONTEXT, 0)?.toString().orEmpty()
        val correction = SuggestionEngine.suggest(before, personalModel, currentLanguageTag)
            .firstOrNull { it.kind == SuggestionKind.CORRECTION }
            ?: return false
        val original = before.takeLast(correction.replaceBeforeCursor)

        connection.beginBatchEdit()
        return try {
            if (!connection.deleteSurroundingText(correction.replaceBeforeCursor, 0)) {
                false
            } else if (connection.commitText(correction.text, 1)) {
                true
            } else {
                connection.commitText(original, 1)
                false
            }
        } finally {
            connection.endBatchEdit()
        }
    }

    private fun consumeObservedFinalWord(): Boolean {
        val before = currentInputConnection
            ?.getTextBeforeCursor(SUGGESTION_CONTEXT, 0)
            ?.toString()
            .orEmpty()
        return observedTextSuffix.consumeIfUnchanged(before)
    }

    private fun commitObservedText(
        text: String,
        languageTag: String = currentLanguageTag,
    ): Boolean {
        if (text.isBlank()) return false
        val connection = currentInputConnection ?: return false
        val before = connection.getTextBeforeCursor(SUGGESTION_CONTEXT, 0)?.toString().orEmpty()
        val plan = TextInsertionFormatter.planInsertion(text, before)
        if (plan.text.isBlank()) return false
        val removedText = before.takeLast(plan.deleteBeforeCursor)

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
            learnCommittedText(text, before.dropLast(plan.deleteBeforeCursor), languageTag)
            observeCommittedText(plan.text)
        }
        return didCommit
    }

    private fun observeCommittedText(text: String) {
        val before = currentInputConnection
            ?.getTextBeforeCursor(SUGGESTION_CONTEXT, 0)
            ?.toString()
            .orEmpty()
        observedTextSuffix.observe(text, before)
    }

    private fun cancelCorrection() {
        correctionJob?.cancel()
        correctionJob = null
        isCorrecting = false
    }

    private fun beginCorrectionUndo(
        state: CorrectionUndoState,
        durationSeconds: Int,
        learning: PendingCorrectionLearning,
    ) {
        clearCorrectionUndo()
        pendingCorrectionUndo = state
        pendingCorrectionLearning = learning
        canUndoCorrection = true
        correctionUndoJob = scope.launch {
            delay(durationSeconds.coerceIn(1, 10) * 1_000L)
            clearCorrectionUndo()
        }
    }

    private fun clearCorrectionUndo(acceptLearning: Boolean = true) {
        correctionUndoJob?.cancel()
        correctionUndoJob = null
        if (acceptLearning) {
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
        val state = undo ?: return false
        val connection = currentInputConnection ?: return false
        val before = connection.getTextBeforeCursor(
            state.anchorBefore.length + state.replacementText.length,
            0,
        )?.toString().orEmpty()
        val after = connection.getTextAfterCursor(state.anchorAfter.length, 0)
            ?.toString().orEmpty()
        return state.matches(before, after)
    }

    private fun refreshTypingState() {
        if (secureField) {
            suggestions = emptyList()
            return
        }
        val before = currentInputConnection
            ?.getTextBeforeCursor(SUGGESTION_CONTEXT, 0)
            ?.toString()
            .orEmpty()
        observedTextSuffix.retainIfUnchanged(before)
        keyboardState.updateAutoShift(before)
        suggestions = SuggestionEngine.suggest(
            before,
            personalModel,
            currentLanguageTag,
            suggestionsAllowed = allowsDictionarySuggestions,
        )
    }

    private fun showBaselineStatus() {
        if (secureField) {
            setStatus("Normal typing only in secure fields.", transient = false)
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
        val options = info?.imeOptions ?: return EditorInfo.IME_ACTION_NONE
        if (options and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0) return EditorInfo.IME_ACTION_NONE
        return options and EditorInfo.IME_MASK_ACTION
    }

    private fun resolveLanguageTag(info: EditorInfo?): String {
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
        return LanguageSupport.preferredTag(hintedTags, deviceTags)
    }

    private fun isSecureInputType(inputType: Int): Boolean {
        val inputClass = inputType and InputType.TYPE_MASK_CLASS
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        return (inputClass == InputType.TYPE_CLASS_TEXT && variation in setOf(
            InputType.TYPE_TEXT_VARIATION_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
        )) || (inputClass == InputType.TYPE_CLASS_NUMBER &&
            variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD)
    }

    private data class CorrectionSnapshot(
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

    private enum class CorrectionTarget { Selection, CurrentSentence }

    private companion object {
        const val MAX_CONTEXT = 1_000
        const val ANCHOR_LENGTH = 64
        const val SUGGESTION_CONTEXT = 64
        const val STATUS_LIFETIME_MS = 4_000L
        const val PERSONAL_MODEL_PREFS = "personal_language_model"
        const val PERSONAL_MODEL_KEY = "model"
        val WORD_BOUNDARY_PUNCTUATION = setOf('.', ',', '?', '!', ';', ':')
    }
}
