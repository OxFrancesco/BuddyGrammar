package com.francescooddo.buddygrammar.ime

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.text.InputType
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.francescooddo.buddygrammar.core.BuddyGrammarApi
import com.francescooddo.buddygrammar.core.PreferencesRepository
import com.francescooddo.buddygrammar.core.TextContextExtractor
import com.francescooddo.buddygrammar.core.TextCorrectionCandidate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class BuddyGrammarImeService : InputMethodService() {
    private val preferences by lazy { PreferencesRepository(this) }
    private val api = BuddyGrammarApi()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var rootView: LinearLayout? = null
    private var statusView: TextView? = null
    private var starButton: Button? = null
    private var correctionJob: Job? = null
    private var symbols = false
    private var uppercase = true
    private var secureField = false

    override fun onCreateInputView(): View = LinearLayout(this).also { root ->
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(dp(5), dp(7), dp(5), dp(7))
        root.setBackgroundColor(Color.rgb(235, 235, 241))
        rootView = root
        renderKeyboard()
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        secureField = info?.inputType?.let(::isSecureInputType) ?: false
        val inputClass = info?.inputType?.and(InputType.TYPE_MASK_CLASS)
        symbols = inputClass == InputType.TYPE_CLASS_NUMBER ||
            inputClass == InputType.TYPE_CLASS_PHONE ||
            inputClass == InputType.TYPE_CLASS_DATETIME
        uppercase = !symbols
        cancelCorrection()
        renderKeyboard()
        showBaselineStatus()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        cancelCorrection()
        super.onFinishInputView(finishingInput)
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun renderKeyboard() {
        val root = rootView ?: return
        root.removeAllViews()
        root.addView(accessoryRow())
        if (symbols) {
            addCharacterRow(root, "1234567890".map(Char::toString))
            addCharacterRow(root, listOf("-", "/", ":", ";", "(", ")", "\$", "&", "@", "\""))
            val lastRow = row()
            listOf(".", ",", "?", "!", "'", "[", "]", "_").forEach { key ->
                lastRow.addView(characterKey(key), weightedKeyParams())
            }
            lastRow.addView(functionKey("⌫", "Delete") { deleteBackward() }, fixedKeyParams(52))
            root.addView(lastRow, rowParams())
        } else {
            addCharacterRow(root, "qwertyuiop".map(Char::toString))
            addCharacterRow(root, "asdfghjkl".map(Char::toString), horizontalInset = 13)
            val lastRow = row()
            lastRow.addView(
                functionKey(if (uppercase) "⇧" else "⇧", if (uppercase) "Shift on" else "Shift off") {
                    uppercase = !uppercase
                    renderKeyboard()
                },
                fixedKeyParams(52),
            )
            "zxcvbnm".map(Char::toString).forEach { key ->
                lastRow.addView(characterKey(key), weightedKeyParams())
            }
            lastRow.addView(functionKey("⌫", "Delete") { deleteBackward() }, fixedKeyParams(52))
            root.addView(lastRow, rowParams())
        }
        root.addView(controlRow(), rowParams())
        showBaselineStatus()
    }

    private fun accessoryRow(): View = row().apply {
        setPadding(dp(2), 0, dp(2), dp(3))
        statusView = TextView(this@BuddyGrammarImeService).also { status ->
            status.textSize = 11f
            status.setTextColor(Color.DKGRAY)
            status.maxLines = 1
            status.gravity = Gravity.CENTER_VERTICAL
            status.contentDescription = "BuddyGrammar keyboard status"
            addView(status, LinearLayout.LayoutParams(0, dp(34), 1f))
        }
        addView(
            functionKey("🎙", "Insert latest BuddyGrammar dictation", prominent = false) {
                insertPendingTranscript()
            },
            fixedKeyParams(46, 34),
        )
        starButton = functionKey("★", "Correct selected text or current sentence", prominent = true) {
            correctCurrentText()
        }.also { addView(it, fixedKeyParams(50, 34)) }
    }

    private fun controlRow(): View = row().apply {
        addView(functionKey(if (symbols) "ABC" else "123", "Change keyboard layout") {
            localEdit()
            symbols = !symbols
            uppercase = !symbols
            renderKeyboard()
        }, fixedKeyParams(56))
        addView(functionKey("🌐", "Switch keyboard") { switchKeyboard() }, fixedKeyParams(48))
        addView(characterKey(" ", label = "space"), LinearLayout.LayoutParams(0, dp(44), 1f).withMargins())
        addView(functionKey("↵", "Return") { insertReturn() }, fixedKeyParams(56))
    }

    private fun addCharacterRow(root: LinearLayout, keys: List<String>, horizontalInset: Int = 0) {
        val row = row().apply { setPadding(dp(horizontalInset), 0, dp(horizontalInset), 0) }
        keys.forEach { key -> row.addView(characterKey(key), weightedKeyParams()) }
        root.addView(row, rowParams())
    }

    private fun characterKey(value: String, label: String = value): Button = keyButton(
        text = if (!symbols && uppercase) value.uppercase() else if (value == " ") "space" else value,
        contentDescription = label,
        prominent = false,
    ) {
        localEdit()
        currentInputConnection?.commitText(
            if (!symbols && uppercase) value.uppercase() else value,
            1,
        )
        if (!symbols && uppercase) {
            uppercase = false
            renderKeyboard()
        }
    }

    private fun functionKey(
        text: String,
        description: String,
        prominent: Boolean = false,
        action: () -> Unit,
    ): Button = keyButton(text, description, prominent, action)

    private fun keyButton(
        text: String,
        contentDescription: String,
        prominent: Boolean,
        action: () -> Unit,
    ): Button = Button(this).apply {
        this.text = text
        this.contentDescription = contentDescription
        isAllCaps = false
        textSize = if (text.length > 3) 12f else 19f
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        setTextColor(if (prominent) Color.WHITE else Color.rgb(25, 25, 28))
        minWidth = 0
        minimumWidth = 0
        minHeight = 0
        minimumHeight = 0
        setPadding(dp(2), 0, dp(2), 0)
        background = roundedBackground(
            if (prominent) Color.rgb(109, 74, 255) else Color.WHITE,
            radius = 8,
        )
        setOnClickListener { action() }
    }

    private fun deleteBackward() {
        localEdit()
        val connection = currentInputConnection ?: return
        if (!connection.deleteSurroundingTextInCodePoints(1, 0)) {
            connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
            connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
        }
    }

    private fun insertReturn() {
        localEdit()
        val action = currentInputEditorInfo?.imeOptions?.and(EditorInfo.IME_MASK_ACTION)
        val handledAction = action != null && action != EditorInfo.IME_ACTION_NONE &&
            action != EditorInfo.IME_ACTION_UNSPECIFIED &&
            currentInputConnection?.performEditorAction(action) == true
        if (!handledAction) currentInputConnection?.commitText("\n", 1)
        if (!symbols) {
            uppercase = true
            renderKeyboard()
        }
    }

    private fun switchKeyboard() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && shouldOfferSwitchingToNextInputMethod()) {
            switchToNextInputMethod(false)
        } else {
            getSystemService(InputMethodManager::class.java).showInputMethodPicker()
        }
    }

    private fun correctCurrentText() {
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
            setStatus("Select text or type a sentence first.", error = true)
            return
        }

        setStatus("Correcting…")
        starButton?.isEnabled = false
        correctionJob = scope.launch {
            try {
                val corrected = api.correct(
                    text = snapshot.candidate.requestText,
                    clientId = preferences.installationId(),
                    modelId = settings.modelId,
                    instruction = settings.correctionInstruction,
                )
                val replacement = snapshot.candidate.replacement(corrected)
                val didApply = applyCorrection(snapshot, replacement)
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
                starButton?.isEnabled = true
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
        val before = connection.getTextBeforeCursor(MAX_CONTEXT + ANCHOR_LENGTH, 0)
            ?.toString().orEmpty()
        val after = connection.getTextAfterCursor(MAX_CONTEXT + ANCHOR_LENGTH, 0)
            ?.toString().orEmpty()
        val cursorCandidate = TextContextExtractor.currentSentence(before, after, MAX_CONTEXT)
            ?: return null
        return CorrectionSnapshot(
            target = CorrectionTarget.CursorSentence,
            candidate = cursorCandidate.candidate,
            textBeforeCursor = cursorCandidate.textBeforeCursor,
            textAfterCursor = cursorCandidate.textAfterCursor,
            anchorBefore = before.removeSuffix(cursorCandidate.textBeforeCursor).takeLast(ANCHOR_LENGTH),
            anchorAfter = after.removePrefix(cursorCandidate.textAfterCursor).take(ANCHOR_LENGTH),
        )
    }

    private fun applyCorrection(snapshot: CorrectionSnapshot, replacement: String): Boolean {
        val connection = currentInputConnection ?: return false
        if (!snapshotStillMatches(snapshot)) return false
        connection.beginBatchEdit()
        try {
            return when (snapshot.target) {
                CorrectionTarget.Selection -> connection.commitText(replacement, 1)
                CorrectionTarget.CursorSentence -> {
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
            CorrectionTarget.CursorSentence -> {
                val expectedBefore = snapshot.anchorBefore + snapshot.textBeforeCursor
                val expectedAfter = snapshot.textAfterCursor + snapshot.anchorAfter
                connection.getTextBeforeCursor(expectedBefore.length, 0)?.toString() == expectedBefore &&
                    connection.getTextAfterCursor(expectedAfter.length, 0)?.toString() == expectedAfter
            }
        }
    }

    private fun insertPendingTranscript() {
        localEdit()
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
        if (currentInputConnection?.commitText(transcript.text, 1) == true) {
            preferences.clearPendingTranscript()
            setStatus("Dictation inserted.")
        } else {
            setStatus("The editor rejected the dictation. It is still saved.", error = true)
        }
    }

    private fun localEdit() {
        cancelCorrection()
        showBaselineStatus()
    }

    private fun cancelCorrection() {
        correctionJob?.cancel()
        correctionJob = null
        starButton?.isEnabled = true
    }

    private fun showBaselineStatus() {
        when {
            secureField -> setStatus("Normal typing only in secure fields.")
            !preferences.loadSettings().hasAcceptedCloudProcessing ->
                setStatus("Allow cloud processing in BuddyGrammar to use ★.", error = true)
            else -> setStatus("Select text or place the cursor after a sentence, then tap ★.")
        }
    }

    private fun setStatus(message: String, error: Boolean = false) {
        statusView?.text = message
        statusView?.setTextColor(if (error) Color.rgb(180, 90, 0) else Color.DKGRAY)
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

    private fun row() = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
    }

    private fun rowParams() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT,
    ).apply { bottomMargin = dp(5) }

    private fun weightedKeyParams() = LinearLayout.LayoutParams(0, dp(44), 1f).withMargins()

    private fun fixedKeyParams(widthDp: Int, heightDp: Int = 44) =
        LinearLayout.LayoutParams(dp(widthDp), dp(heightDp)).withMargins()

    private fun LinearLayout.LayoutParams.withMargins(): LinearLayout.LayoutParams = apply {
        marginStart = dp(2)
        marginEnd = dp(2)
    }

    private fun roundedBackground(color: Int, radius: Int) = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        setColor(color)
        cornerRadius = dp(radius).toFloat()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private data class CorrectionSnapshot(
        val target: CorrectionTarget,
        val candidate: TextCorrectionCandidate,
        val textBeforeCursor: String,
        val textAfterCursor: String,
        val anchorBefore: String,
        val anchorAfter: String,
    )

    private enum class CorrectionTarget { Selection, CursorSentence }

    private companion object {
        const val MAX_CONTEXT = 1_000
        const val ANCHOR_LENGTH = 64
    }
}
