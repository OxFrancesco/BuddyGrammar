package com.francescooddo.buddygrammar.ime

import android.text.InputType
import android.view.inputmethod.EditorInfo
import com.francescooddo.buddygrammar.core.CatalogFieldKind

enum class EditorFieldKind(val catalogFieldKind: CatalogFieldKind) {
    TEXT(CatalogFieldKind.TEXT),
    MULTILINE(CatalogFieldKind.MULTILINE),
    LITERAL(CatalogFieldKind.LITERAL),
    NAME(CatalogFieldKind.NAME),
    SEARCH(CatalogFieldKind.SEARCH),
    EMAIL(CatalogFieldKind.EMAIL),
    URL(CatalogFieldKind.URL),
    NUMBER(CatalogFieldKind.NUMBER),
    DECIMAL(CatalogFieldKind.DECIMAL),
    PHONE(CatalogFieldKind.PHONE),
    DATETIME(CatalogFieldKind.DATETIME),
    CODE(CatalogFieldKind.CODE),
    ONE_TIME_CODE(CatalogFieldKind.ONE_TIME_CODE),
    PASSWORD(CatalogFieldKind.PASSWORD),
    ;

    val isSensitive: Boolean get() = this == ONE_TIME_CODE || this == PASSWORD
    val isCodeLike: Boolean get() = this == CODE
    val isStructured: Boolean get() = this in STRUCTURED_KINDS

    private companion object {
        val STRUCTURED_KINDS = setOf(NAME, EMAIL, URL, NUMBER, DECIMAL, PHONE, DATETIME)
    }
}

enum class CapabilityDenialReason {
    SENSITIVE_FIELD,
    STRUCTURED_FIELD,
    CODE_FIELD,
    EDITOR_DISABLED_ASSISTANCE,
    EDITOR_DISABLED_PERSONALIZED_LEARNING,
    CLOUD_CONSENT_REQUIRED,
    CLOUD_TRANSPORT_UNAVAILABLE,
    PLATFORM_VOICE_UNAVAILABLE,
    EDITOR_CURSOR_UNAVAILABLE,
    EDITOR_CONTEXT_UNAVAILABLE,
    EDITOR_COMPOSITION_UNAVAILABLE,
    SHARED_TRANSCRIPT_UNAVAILABLE,
}

data class CapabilityDecision(
    val denialReason: CapabilityDenialReason?,
) {
    val isAllowed: Boolean get() = denialReason == null

    companion object {
        val ALLOWED = CapabilityDecision(denialReason = null)

        fun denied(reason: CapabilityDenialReason) = CapabilityDecision(reason)
    }
}

fun CapabilityDecision.denialMessage(featureName: String): String = when (denialReason) {
    CapabilityDenialReason.SENSITIVE_FIELD -> "$featureName is unavailable in sensitive fields."
    CapabilityDenialReason.STRUCTURED_FIELD ->
        "$featureName is unavailable in structured fields such as email, URL, and names."
    CapabilityDenialReason.CODE_FIELD -> "$featureName is unavailable in code fields."
    CapabilityDenialReason.EDITOR_DISABLED_ASSISTANCE ->
        "$featureName is disabled by this editor."
    CapabilityDenialReason.EDITOR_DISABLED_PERSONALIZED_LEARNING ->
        "Personalized learning is disabled by this editor."
    CapabilityDenialReason.CLOUD_CONSENT_REQUIRED ->
        "Allow cloud processing in BuddyGrammar to use $featureName."
    CapabilityDenialReason.CLOUD_TRANSPORT_UNAVAILABLE ->
        "$featureName cannot reach BuddyGrammar from this keyboard."
    CapabilityDenialReason.PLATFORM_VOICE_UNAVAILABLE ->
        "Voice typing is unavailable on this device."
    CapabilityDenialReason.EDITOR_CURSOR_UNAVAILABLE ->
        "Cursor movement is unavailable in this editor."
    CapabilityDenialReason.EDITOR_CONTEXT_UNAVAILABLE ->
        "$featureName cannot read context from this editor."
    CapabilityDenialReason.EDITOR_COMPOSITION_UNAVAILABLE ->
        "$featureName cannot use composing text in this editor."
    CapabilityDenialReason.SHARED_TRANSCRIPT_UNAVAILABLE ->
        "There is no recent saved dictation to insert."
    null -> ""
}

data class EditorPrivacyContext(
    val fieldKind: EditorFieldKind,
    val secure: Boolean = false,
    val editorAllowsSuggestions: Boolean = true,
    val editorAllowsPersonalizedLearning: Boolean = true,
    val cloudConsentGranted: Boolean,
    val cloudTransportAvailable: Boolean = true,
    val platformVoiceAvailable: Boolean = true,
    val editorCanMoveCursor: Boolean = true,
    val sharedTranscriptAvailable: Boolean = true,
    val editorCanReadContext: Boolean = true,
    val editorCanUseComposition: Boolean = true,
)

data class EditorCapabilities(
    val fieldKind: EditorFieldKind,
    val presentationFieldKind: EditorFieldKind,
    val secure: Boolean,
    val suggestions: CapabilityDecision,
    val learning: CapabilityDecision,
    val autoCorrection: CapabilityDecision,
    val swipe: CapabilityDecision,
    val moveCursor: CapabilityDecision,
    val starCorrection: CapabilityDecision,
    val cloudHandwriting: CapabilityDecision,
    val voice: CapabilityDecision,
    val pendingTranscript: CapabilityDecision,
    val readContext: CapabilityDecision,
    val useComposition: CapabilityDecision,
    val localHandwriting: CapabilityDecision,
    val literalTools: CapabilityDecision,
    val directLocalInsertion: CapabilityDecision,
    val clipboardInsertion: CapabilityDecision,
) {
    val isSecureField: Boolean get() = secure || fieldKind.isSensitive
    val isStructuredField: Boolean get() = fieldKind.isStructured
    val isCodeLikeField: Boolean get() = fieldKind.isCodeLike

    companion object {
        val INACTIVE = EditorCapabilityPolicy.evaluate(
            EditorPrivacyContext(
                fieldKind = EditorFieldKind.CODE,
                editorAllowsSuggestions = false,
                editorAllowsPersonalizedLearning = false,
                cloudConsentGranted = false,
                cloudTransportAvailable = false,
                platformVoiceAvailable = false,
                editorCanMoveCursor = false,
                sharedTranscriptAvailable = false,
            ),
        )
    }
}

internal fun EditorCapabilities.allowsCloudCorrectionDispatch(): Boolean =
    starCorrection.isAllowed && readContext.isAllowed

/** One pure privacy and editor-primitive decision for every keyboard feature. */
object EditorCapabilityPolicy {
    fun evaluate(context: EditorPrivacyContext): EditorCapabilities {
        val fieldKind = if (context.secure && !context.fieldKind.isSensitive) {
            EditorFieldKind.PASSWORD
        } else {
            context.fieldKind
        }
        val assistanceDisabled =
            !context.editorAllowsSuggestions || fieldKind == EditorFieldKind.LITERAL
        val presentationFieldKind = when {
            context.secure || fieldKind.isSensitive -> EditorFieldKind.PASSWORD
            assistanceDisabled && fieldKind in setOf(
                EditorFieldKind.TEXT,
                EditorFieldKind.MULTILINE,
            ) -> EditorFieldKind.LITERAL
            else -> fieldKind
        }
        val fieldDenial = when {
            context.secure || fieldKind.isSensitive -> CapabilityDenialReason.SENSITIVE_FIELD
            fieldKind.isCodeLike -> CapabilityDenialReason.CODE_FIELD
            fieldKind.isStructured -> CapabilityDenialReason.STRUCTURED_FIELD
            else -> null
        }
        val predictionDenial = fieldDenial ?: if (assistanceDisabled) {
            CapabilityDenialReason.EDITOR_DISABLED_ASSISTANCE
        } else {
            null
        }
        val predictions = decision(predictionDenial)
        val learning = decision(
            predictionDenial
                ?: CapabilityDenialReason.STRUCTURED_FIELD.takeIf {
                    fieldKind == EditorFieldKind.SEARCH
                }
                ?: CapabilityDenialReason.EDITOR_DISABLED_PERSONALIZED_LEARNING.takeIf {
                    !context.editorAllowsPersonalizedLearning
                },
        )
        val buddyFieldDenial = fieldDenial
            ?: CapabilityDenialReason.STRUCTURED_FIELD.takeIf {
                fieldKind == EditorFieldKind.SEARCH
            }
            ?: CapabilityDenialReason.EDITOR_DISABLED_ASSISTANCE.takeIf {
                !context.editorAllowsSuggestions
            }
        val buddy = decision(
            buddyFieldDenial
                ?: CapabilityDenialReason.CLOUD_CONSENT_REQUIRED.takeIf {
                    !context.cloudConsentGranted
                }
                ?: CapabilityDenialReason.CLOUD_TRANSPORT_UNAVAILABLE.takeIf {
                    !context.cloudTransportAvailable
                },
        )
        val voice = decision(
            fieldDenial
                ?: CapabilityDenialReason.PLATFORM_VOICE_UNAVAILABLE.takeIf {
                    !context.platformVoiceAvailable
                },
        )
        val pendingTranscript = decision(
            fieldDenial
                ?: CapabilityDenialReason.STRUCTURED_FIELD.takeIf {
                    fieldKind == EditorFieldKind.SEARCH
                }
                ?: CapabilityDenialReason.EDITOR_DISABLED_ASSISTANCE.takeIf {
                    !context.editorAllowsSuggestions
                }
                ?: CapabilityDenialReason.SHARED_TRANSCRIPT_UNAVAILABLE.takeIf {
                    !context.sharedTranscriptAvailable
                },
        )
        val readContext = decision(
            predictionDenial
                ?: CapabilityDenialReason.EDITOR_CONTEXT_UNAVAILABLE.takeIf {
                    !context.editorCanReadContext
                },
        )
        val useComposition = decision(
            predictionDenial
                ?: CapabilityDenialReason.EDITOR_COMPOSITION_UNAVAILABLE.takeIf {
                    !context.editorCanUseComposition
                },
        )
        val literalTools = decision(
            fieldDenial?.takeUnless { it == CapabilityDenialReason.CODE_FIELD },
        )
        val directLocalInsertion = decision(
            fieldDenial?.takeUnless {
                it == CapabilityDenialReason.STRUCTURED_FIELD
            }
                ?: CapabilityDenialReason.EDITOR_DISABLED_ASSISTANCE.takeIf {
                    assistanceDisabled
                },
        )

        return EditorCapabilities(
            fieldKind = fieldKind,
            presentationFieldKind = presentationFieldKind,
            secure = context.secure || fieldKind.isSensitive,
            suggestions = predictions,
            learning = learning,
            autoCorrection = predictions,
            swipe = predictions,
            moveCursor = decision(
                CapabilityDenialReason.EDITOR_CURSOR_UNAVAILABLE.takeIf {
                    !context.editorCanMoveCursor
                },
            ),
            starCorrection = buddy,
            cloudHandwriting = buddy,
            voice = voice,
            pendingTranscript = pendingTranscript,
            readContext = readContext,
            useComposition = useComposition,
            localHandwriting = predictions,
            literalTools = literalTools,
            directLocalInsertion = directLocalInsertion,
            clipboardInsertion = directLocalInsertion,
        )
    }

    fun evaluateAndroid(
        inputType: Int,
        imeOptions: Int,
        cloudConsentGranted: Boolean,
        privateImeOptions: String? = null,
        cloudTransportAvailable: Boolean = true,
        platformVoiceAvailable: Boolean = true,
        editorCanMoveCursor: Boolean = true,
        sharedTranscriptAvailable: Boolean = true,
        editorCanReadContext: Boolean = true,
        editorCanUseComposition: Boolean = true,
    ): EditorCapabilities {
        val fieldKind = fieldKind(inputType, imeOptions, privateImeOptions)
        return evaluate(
            EditorPrivacyContext(
                fieldKind = fieldKind,
                secure = fieldKind.isSensitive,
                editorAllowsSuggestions =
                    inputType and InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS == 0,
                editorAllowsPersonalizedLearning =
                    imeOptions and EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING == 0,
                cloudConsentGranted = cloudConsentGranted,
                cloudTransportAvailable = cloudTransportAvailable,
                platformVoiceAvailable = platformVoiceAvailable,
                editorCanMoveCursor = editorCanMoveCursor,
                sharedTranscriptAvailable = sharedTranscriptAvailable,
                editorCanReadContext = editorCanReadContext,
                editorCanUseComposition = editorCanUseComposition,
            ),
        )
    }

    private fun fieldKind(
        inputType: Int,
        imeOptions: Int,
        privateImeOptions: String?,
    ): EditorFieldKind {
        val inputClass = inputType and InputType.TYPE_MASK_CLASS
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        if (inputClass == InputType.TYPE_CLASS_TEXT && isCodeEditor(privateImeOptions)) {
            return EditorFieldKind.CODE
        }
        if (inputClass == InputType.TYPE_CLASS_TEXT && variation in SECURE_TEXT_VARIATIONS) {
            return EditorFieldKind.PASSWORD
        }
        if (
            inputClass == InputType.TYPE_CLASS_NUMBER &&
            variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
        ) {
            return EditorFieldKind.ONE_TIME_CODE
        }
        return when (inputClass) {
            InputType.TYPE_CLASS_NUMBER -> if (
                inputType and InputType.TYPE_NUMBER_FLAG_DECIMAL != 0
            ) {
                EditorFieldKind.DECIMAL
            } else {
                EditorFieldKind.NUMBER
            }
            InputType.TYPE_CLASS_PHONE -> EditorFieldKind.PHONE
            InputType.TYPE_CLASS_DATETIME -> EditorFieldKind.DATETIME
            InputType.TYPE_CLASS_TEXT -> when {
                variation in EMAIL_TEXT_VARIATIONS -> EditorFieldKind.EMAIL
                variation == InputType.TYPE_TEXT_VARIATION_URI -> EditorFieldKind.URL
                variation in NAME_TEXT_VARIATIONS -> EditorFieldKind.NAME
                imeOptions and EditorInfo.IME_MASK_ACTION == EditorInfo.IME_ACTION_SEARCH ||
                    variation == InputType.TYPE_TEXT_VARIATION_FILTER -> EditorFieldKind.SEARCH
                inputType and InputType.TYPE_TEXT_FLAG_MULTI_LINE != 0 -> EditorFieldKind.MULTILINE
                else -> EditorFieldKind.TEXT
            }
            else -> EditorFieldKind.CODE
        }
    }

    private fun isCodeEditor(privateImeOptions: String?): Boolean {
        val value = privateImeOptions?.lowercase().orEmpty()
        return CODE_HINTS.any(value::contains)
    }

    private fun decision(reason: CapabilityDenialReason?): CapabilityDecision =
        reason?.let(CapabilityDecision::denied) ?: CapabilityDecision.ALLOWED

    private val SECURE_TEXT_VARIATIONS = setOf(
        InputType.TYPE_TEXT_VARIATION_PASSWORD,
        InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
        InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
    )
    private val EMAIL_TEXT_VARIATIONS = setOf(
        InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
        InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS,
    )
    private val NAME_TEXT_VARIATIONS = setOf(
        InputType.TYPE_TEXT_VARIATION_PERSON_NAME,
        InputType.TYPE_TEXT_VARIATION_POSTAL_ADDRESS,
        InputType.TYPE_TEXT_VARIATION_PHONETIC,
    )
    private val CODE_HINTS = setOf("code", "terminal", "shell", "monospace")
}
