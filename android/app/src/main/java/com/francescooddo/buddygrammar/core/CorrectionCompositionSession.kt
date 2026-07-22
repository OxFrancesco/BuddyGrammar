package com.francescooddo.buddygrammar.core

import java.text.BreakIterator
import java.util.Locale
import java.util.UUID

/**
 * Editor seam for [CorrectionCompositionSession]. Replacements are
 * compare-and-swap operations, preventing a stale receipt from overwriting an
 * editor observation it did not create.
 */
interface CorrectionCompositionEditor {
    val correctionCompositionText: String

    fun replaceCorrectionCompositionSuffix(
        expectedSuffix: String,
        replacement: String,
    ): Boolean

    fun deleteCorrectionCompositionBackward(): Boolean
}

/** Deterministic value-state adapter used by conformance and pure callers. */
class CorrectionCompositionValueEditor(initialText: String) : CorrectionCompositionEditor {
    var text: String = initialText
        private set

    override val correctionCompositionText: String get() = text

    override fun replaceCorrectionCompositionSuffix(
        expectedSuffix: String,
        replacement: String,
    ): Boolean {
        if (!text.endsWith(expectedSuffix)) return false
        text = text.dropLast(expectedSuffix.length) + replacement
        return true
    }

    override fun deleteCorrectionCompositionBackward(): Boolean {
        if (text.isEmpty()) return false
        val iterator = BreakIterator.getCharacterInstance(Locale.ROOT)
        iterator.setText(text)
        val boundary = iterator.preceding(text.length)
        text = if (boundary == BreakIterator.DONE) "" else text.substring(0, boundary)
        return true
    }

    /** Pair with [CorrectionCompositionSession.externalEditObserved]. */
    fun replaceTextExternally(text: String) {
        this.text = text
    }
}

enum class CorrectionCompositionReceiptMode {
    AUTOMATIC,
    EXPLICIT,
}

data class CorrectionCompositionAsyncStamp(
    val fieldEpoch: Long,
    val fieldIdentifier: String,
)

data class CorrectionCompositionLearning(
    val text: String,
    val originalText: String,
    val precedingContext: String,
    val languageTag: String,
    val source: String,
)

data class CorrectionCompositionRejection(
    val source: String,
    val rejectedText: String,
    val restoredText: String,
    val precedingContext: String,
    val languageTag: String,
)

data class CorrectionCompositionEffect(
    val didMutateEditor: Boolean = false,
    val consumedBackspace: Boolean = false,
    val ignored: Boolean = false,
    val acceptedLearning: CorrectionCompositionLearning? = null,
    val rejection: CorrectionCompositionRejection? = null,
)

data class CorrectionCompositionSessionSnapshot(
    val fieldEpoch: Long,
    val fieldIdentifier: String,
    val receiptId: UUID?,
    val receiptMode: CorrectionCompositionReceiptMode?,
    val receiptSource: String?,
    val originalText: String?,
    val replacementText: String?,
) {
    val hasActiveReceipt: Boolean get() = receiptId != null
    val hasPendingLearning: Boolean get() = hasActiveReceipt
}

/**
 * Owns automatic and explicit correction composition as one deep module:
 * editor mutation, field epochs, stale async gating, receipt expiry, deferred
 * learning, external invalidation, and both undo modes move together.
 */
class CorrectionCompositionSession(
    initialFieldEpoch: Long = 0,
    fieldIdentifier: String = "unbound",
) {
    private sealed interface NativeReceipt {
        data class Automatic(val value: LocalCorrectionReceipt) : NativeReceipt
        data object Explicit : NativeReceipt
    }

    private data class ActiveReceipt(
        val id: UUID,
        val mode: CorrectionCompositionReceiptMode,
        val native: NativeReceipt,
        val source: String,
        val originalText: String,
        val replacementText: String,
        val boundaryText: String,
        val precedingContext: String,
        val languageTag: String,
        val fieldEpoch: Long,
        val fieldIdentifier: String,
        val expectedEditorText: String,
        val expiresAtMilliseconds: Long,
    ) {
        val learning: CorrectionCompositionLearning
            get() = CorrectionCompositionLearning(
                text = replacementText,
                originalText = originalText,
                precedingContext = precedingContext,
                languageTag = languageTag,
                source = source,
            )

        val rejection: CorrectionCompositionRejection
            get() = CorrectionCompositionRejection(
                source = source,
                rejectedText = replacementText,
                restoredText = originalText,
                precedingContext = precedingContext,
                languageTag = languageTag,
            )
    }

    private var fieldEpoch: Long = initialFieldEpoch
    private var fieldIdentifier: String = fieldIdentifier
    private var activeReceipt: ActiveReceipt? = null

    val snapshot: CorrectionCompositionSessionSnapshot
        get() = CorrectionCompositionSessionSnapshot(
            fieldEpoch = fieldEpoch,
            fieldIdentifier = fieldIdentifier,
            receiptId = activeReceipt?.id,
            receiptMode = activeReceipt?.mode,
            receiptSource = activeReceipt?.source,
            originalText = activeReceipt?.originalText,
            replacementText = activeReceipt?.replacementText,
        )

    fun captureAsyncStamp() = CorrectionCompositionAsyncStamp(fieldEpoch, fieldIdentifier)

    fun isFresh(stamp: CorrectionCompositionAsyncStamp): Boolean =
        stamp.fieldEpoch == fieldEpoch && stamp.fieldIdentifier == fieldIdentifier

    /** Advances even if a host recycles the same identifier. */
    fun changeField(identifier: String) {
        fieldEpoch += 1
        fieldIdentifier = identifier
        activeReceipt = null
    }

    /** Safe for repeated callbacks about the current field. */
    fun synchronizeField(identifier: String) {
        if (identifier != fieldIdentifier) changeField(identifier)
    }

    fun externalEditObserved() {
        activeReceipt = null
    }

    fun invalidateIfEditorChanged(editor: CorrectionCompositionEditor): Boolean {
        val receipt = activeReceipt ?: return false
        if (receipt.expectedEditorText == editor.correctionCompositionText) return false
        activeReceipt = null
        return true
    }

    fun applyAutomatic(
        editor: CorrectionCompositionEditor,
        originalText: String,
        replacementText: String,
        boundaryText: String,
        precedingContext: String,
        languageTag: String,
        source: String,
        atMilliseconds: Long,
        receiptLifetimeMilliseconds: Long = DEFAULT_RECEIPT_LIFETIME_MS,
    ): CorrectionCompositionEffect {
        if (
            !isValidReplacement(originalText, replacementText) || source.isEmpty() ||
            !editor.replaceCorrectionCompositionSuffix(
                originalText,
                replacementText + boundaryText,
            )
        ) {
            return CorrectionCompositionEffect(ignored = true)
        }
        val recorded = recordAutomaticApplication(
            editor = editor,
            originalText = originalText,
            replacementText = replacementText,
            boundaryText = boundaryText,
            precedingContext = precedingContext,
            languageTag = languageTag,
            source = source,
            atMilliseconds = atMilliseconds,
            receiptLifetimeMilliseconds = receiptLifetimeMilliseconds,
        )
        return CorrectionCompositionEffect(
            // The CAS mutation already succeeded. Some InputConnections lag
            // when echoing their new context; that can drop the receipt but
            // must not be reported as if the editor mutation never happened.
            didMutateEditor = true,
            ignored = recorded.ignored,
        )
    }

    fun applyAsyncAutomatic(
        stamp: CorrectionCompositionAsyncStamp,
        editor: CorrectionCompositionEditor,
        originalText: String,
        replacementText: String,
        boundaryText: String,
        precedingContext: String,
        languageTag: String,
        source: String,
        atMilliseconds: Long,
        receiptLifetimeMilliseconds: Long = DEFAULT_RECEIPT_LIFETIME_MS,
    ): CorrectionCompositionEffect {
        if (!isFresh(stamp)) return CorrectionCompositionEffect(ignored = true)
        return applyAutomatic(
            editor = editor,
            originalText = originalText,
            replacementText = replacementText,
            boundaryText = boundaryText,
            precedingContext = precedingContext,
            languageTag = languageTag,
            source = source,
            atMilliseconds = atMilliseconds,
            receiptLifetimeMilliseconds = receiptLifetimeMilliseconds,
        )
    }

    /** Records a replacement already confirmed by a platform editor. */
    fun recordAutomaticApplication(
        editor: CorrectionCompositionEditor,
        originalText: String,
        replacementText: String,
        boundaryText: String,
        precedingContext: String,
        languageTag: String,
        source: String,
        atMilliseconds: Long,
        receiptLifetimeMilliseconds: Long = DEFAULT_RECEIPT_LIFETIME_MS,
    ): CorrectionCompositionEffect {
        val context = editor.correctionCompositionText
        if (
            !isValidReplacement(originalText, replacementText) || source.isEmpty() ||
            !context.endsWith(replacementText + boundaryText)
        ) {
            activeReceipt = null
            return CorrectionCompositionEffect(ignored = true)
        }
        val native = LocalCorrectionReceipt.create(
            originalText = originalText,
            replacementText = replacementText,
            contextBeforeOriginal = precedingContext,
            boundaryText = boundaryText,
            languageTag = languageTag,
        )
        activeReceipt = ActiveReceipt(
            id = UUID.randomUUID(),
            mode = CorrectionCompositionReceiptMode.AUTOMATIC,
            native = NativeReceipt.Automatic(native),
            source = source,
            originalText = originalText,
            replacementText = replacementText,
            boundaryText = boundaryText,
            precedingContext = precedingContext,
            languageTag = languageTag,
            fieldEpoch = fieldEpoch,
            fieldIdentifier = fieldIdentifier,
            expectedEditorText = context,
            expiresAtMilliseconds = atMilliseconds + receiptLifetimeMilliseconds,
        )
        return CorrectionCompositionEffect()
    }

    fun applyExplicit(
        editor: CorrectionCompositionEditor,
        originalText: String,
        replacementText: String,
        source: String,
        precedingContext: String = "",
        languageTag: String = "",
        atMilliseconds: Long,
        receiptLifetimeMilliseconds: Long = DEFAULT_RECEIPT_LIFETIME_MS,
    ): CorrectionCompositionEffect {
        if (
            !isValidReplacement(originalText, replacementText) || source.isEmpty() ||
            !editor.replaceCorrectionCompositionSuffix(originalText, replacementText)
        ) {
            return CorrectionCompositionEffect(ignored = true)
        }
        val recorded = recordExplicitApplication(
            editor = editor,
            originalText = originalText,
            replacementText = replacementText,
            source = source,
            precedingContext = precedingContext,
            languageTag = languageTag,
            atMilliseconds = atMilliseconds,
            receiptLifetimeMilliseconds = receiptLifetimeMilliseconds,
        )
        return CorrectionCompositionEffect(
            didMutateEditor = true,
            ignored = recorded.ignored,
        )
    }

    /** Records an explicit review proposal already confirmed by a host. */
    fun recordExplicitApplication(
        editor: CorrectionCompositionEditor,
        originalText: String,
        replacementText: String,
        source: String,
        precedingContext: String = "",
        languageTag: String = "",
        atMilliseconds: Long,
        receiptLifetimeMilliseconds: Long = DEFAULT_RECEIPT_LIFETIME_MS,
    ): CorrectionCompositionEffect {
        val context = editor.correctionCompositionText
        if (
            !isValidReplacement(originalText, replacementText) || source.isEmpty() ||
            !context.endsWith(replacementText)
        ) {
            activeReceipt = null
            return CorrectionCompositionEffect(ignored = true)
        }
        activeReceipt = ActiveReceipt(
            id = UUID.randomUUID(),
            mode = CorrectionCompositionReceiptMode.EXPLICIT,
            native = NativeReceipt.Explicit,
            source = source,
            originalText = originalText,
            replacementText = replacementText,
            boundaryText = "",
            precedingContext = precedingContext,
            languageTag = languageTag,
            fieldEpoch = fieldEpoch,
            fieldIdentifier = fieldIdentifier,
            expectedEditorText = context,
            expiresAtMilliseconds = atMilliseconds + receiptLifetimeMilliseconds,
        )
        return CorrectionCompositionEffect()
    }

    fun backspace(editor: CorrectionCompositionEditor): CorrectionCompositionEffect {
        val receipt = currentReceipt(editor)
        val automatic = receipt?.native as? NativeReceipt.Automatic
        val plan = if (receipt?.mode == CorrectionCompositionReceiptMode.AUTOMATIC) {
            automatic?.value?.revertPlan(
                contextBeforeCursor = editor.correctionCompositionText,
                mode = LocalCorrectionRevertMode.BACKSPACE,
            )
        } else {
            null
        }
        if (
            receipt != null && plan != null &&
            editor.replaceCorrectionCompositionSuffix(
                receipt.replacementText + receipt.boundaryText,
                plan.insertText,
            )
        ) {
            activeReceipt = null
            return CorrectionCompositionEffect(
                didMutateEditor = true,
                consumedBackspace = true,
                rejection = receipt.rejection,
            )
        }

        activeReceipt = null
        return CorrectionCompositionEffect(
            didMutateEditor = editor.deleteCorrectionCompositionBackward(),
        )
    }

    fun visibleRevert(editor: CorrectionCompositionEditor): CorrectionCompositionEffect {
        val receipt = currentReceipt(editor)
            ?: return CorrectionCompositionEffect(ignored = true).also { activeReceipt = null }
        val didReplace = when (val native = receipt.native) {
            is NativeReceipt.Automatic -> {
                val plan = native.value.revertPlan(
                    contextBeforeCursor = editor.correctionCompositionText,
                    mode = LocalCorrectionRevertMode.VISIBLE_UNDO,
                ) ?: return CorrectionCompositionEffect(ignored = true).also {
                    activeReceipt = null
                }
                editor.replaceCorrectionCompositionSuffix(
                    receipt.replacementText + receipt.boundaryText,
                    plan.insertText,
                )
            }
            NativeReceipt.Explicit -> editor.replaceCorrectionCompositionSuffix(
                receipt.replacementText,
                receipt.originalText,
            )
        }
        activeReceipt = null
        if (!didReplace) return CorrectionCompositionEffect(ignored = true)
        return CorrectionCompositionEffect(
            didMutateEditor = true,
            rejection = receipt.rejection,
        )
    }

    fun advanceTime(
        milliseconds: Long,
        editor: CorrectionCompositionEditor,
    ): CorrectionCompositionEffect {
        val receipt = activeReceipt
            ?.takeIf { milliseconds >= it.expiresAtMilliseconds }
            ?: return CorrectionCompositionEffect()
        activeReceipt = null
        if (!isReceiptFresh(receipt, editor)) return CorrectionCompositionEffect()
        return CorrectionCompositionEffect(acceptedLearning = receipt.learning)
    }

    /** Completes or discards deferred learning before a known keyboard edit. */
    fun finishActiveReceipt(
        editor: CorrectionCompositionEditor,
        acceptLearning: Boolean,
    ): CorrectionCompositionEffect {
        val receipt = activeReceipt ?: return CorrectionCompositionEffect()
        activeReceipt = null
        if (!acceptLearning || !isReceiptFresh(receipt, editor)) {
            return CorrectionCompositionEffect()
        }
        return CorrectionCompositionEffect(acceptedLearning = receipt.learning)
    }

    private fun isValidReplacement(original: String, replacement: String): Boolean =
        original.isNotEmpty() && replacement.isNotEmpty() && original != replacement

    private fun currentReceipt(editor: CorrectionCompositionEditor): ActiveReceipt? =
        activeReceipt?.takeIf { isReceiptFresh(it, editor) }

    private fun isReceiptFresh(
        receipt: ActiveReceipt,
        editor: CorrectionCompositionEditor,
    ): Boolean = receipt.fieldEpoch == fieldEpoch &&
        receipt.fieldIdentifier == fieldIdentifier &&
        receipt.expectedEditorText == editor.correctionCompositionText

    private companion object {
        const val DEFAULT_RECEIPT_LIFETIME_MS = 3_000L
    }
}
