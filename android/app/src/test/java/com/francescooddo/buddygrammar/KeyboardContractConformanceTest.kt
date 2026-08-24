package com.francescooddo.buddygrammar

import com.francescooddo.buddygrammar.core.CatalogFieldKind
import com.francescooddo.buddygrammar.core.CorrectionCompositionAsyncStamp
import com.francescooddo.buddygrammar.core.CorrectionCompositionEffect
import com.francescooddo.buddygrammar.core.CorrectionCompositionSession
import com.francescooddo.buddygrammar.core.CorrectionCompositionValueEditor
import com.francescooddo.buddygrammar.core.KeyboardCatalog
import com.francescooddo.buddygrammar.core.KeyboardInteractionRouter
import com.francescooddo.buddygrammar.core.InteractionDeadline
import com.francescooddo.buddygrammar.core.InteractionEffect
import com.francescooddo.buddygrammar.core.InteractionFeedback
import com.francescooddo.buddygrammar.core.InteractionInput
import com.francescooddo.buddygrammar.core.InteractionPoint
import com.francescooddo.buddygrammar.core.InteractionTarget
import com.francescooddo.buddygrammar.core.SwipePathSample
import com.francescooddo.buddygrammar.core.SwipeTypingEngine
import com.francescooddo.buddygrammar.core.SwipeWordNormalizer
import com.francescooddo.buddygrammar.core.contractLexicon
import com.francescooddo.buddygrammar.core.adaptive.KeyCandidate
import com.francescooddo.buddygrammar.core.adaptive.TapWordAcceptancePolicy
import com.francescooddo.buddygrammar.core.adaptive.TapWordDecoder
import com.francescooddo.buddygrammar.core.adaptive.TapWordLatticeTap
import com.francescooddo.buddygrammar.ime.CapabilityDecision
import com.francescooddo.buddygrammar.ime.CapabilityDenialReason
import com.francescooddo.buddygrammar.ime.EditorCapabilityPolicy
import com.francescooddo.buddygrammar.ime.EditorFieldKind
import com.francescooddo.buddygrammar.ime.EditorPrivacyContext
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyboardContractConformanceTest {
    @Test
    fun `capability policy replays bundled shared contract`() {
        val suite = fixture("capability-policy")
        assertEquals(1, suite.getInt("schemaVersion"))
        assertEquals(KeyboardCatalog.REVISION, suite.getString("catalogRevision"))

        suite.getJSONArray("cases").objects().forEach { case ->
            val id = case.getString("id")
            val input = case.getJSONObject("input")
            val expected = case.getJSONObject("expect")
            val capabilities = EditorCapabilityPolicy.evaluate(
                EditorPrivacyContext(
                    fieldKind = input.getString("fieldKind").editorFieldKind(),
                    secure = input.getBoolean("secure"),
                    editorAllowsSuggestions = !input.getBoolean("noSuggestions"),
                    editorAllowsPersonalizedLearning =
                        !input.getBoolean("noPersonalizedLearning"),
                    cloudConsentGranted = input.getBoolean("cloudProcessingConsent"),
                    cloudTransportAvailable = input.getBoolean("cloudTransportAvailable"),
                    platformVoiceAvailable = input.getBoolean("platformVoiceAvailable"),
                    editorCanMoveCursor = input.getBoolean("editorCanMoveCursor"),
                    sharedTranscriptAvailable = true,
                ),
            )
            val presentation = KeyboardCatalog.presentation(
                capabilities.presentationFieldKind.catalogFieldKind,
                "en",
            )

            assertEquals(
                id,
                expected.getString("layoutVariant"),
                presentation.fieldKind.layoutVariantId(),
            )
            assertEquals(
                id,
                expected.getBoolean("canSuggest"),
                capabilities.suggestions.isAllowed,
            )
            assertEquals(
                id,
                expected.getBoolean("canLearn"),
                capabilities.learning.isAllowed,
            )
            assertEquals(
                id,
                expected.getBoolean("canAutoCorrect"),
                capabilities.autoCorrection.isAllowed,
            )
            assertEquals(
                id,
                expected.getBoolean("canSwipe"),
                capabilities.swipe.isAllowed,
            )
            assertEquals(
                id,
                expected.getBoolean("canReadContext"),
                capabilities.readContext.isAllowed,
            )
            assertEquals(
                id,
                expected.getBoolean("canUseComposition"),
                capabilities.useComposition.isAllowed,
            )
            assertEquals(
                id,
                expected.getBoolean("canMoveCursor"),
                capabilities.moveCursor.isAllowed,
            )
            assertEquals(
                id,
                expected.getString("buddyFix"),
                capabilities.starCorrection.contractCode(),
            )
            assertEquals(
                id,
                expected.getString("platformVoice"),
                capabilities.voice.contractCode(),
            )
        }
    }

    @Test
    fun `correction receipts replay bundled shared contract`() {
        val suite = fixture("correction-receipts")
        assertEquals(1, suite.getInt("schemaVersion"))
        assertEquals(KeyboardCatalog.REVISION, suite.getString("catalogRevision"))

        suite.getJSONArray("cases").objects().forEach { case ->
            val id = case.getString("id")
            val expected = case.getJSONObject("expect")
            val actual = CorrectionContractDriver.replay(
                input = case.getJSONObject("input"),
                events = case.getJSONArray("events"),
            )

            assertEquals(id, expected.getString("text"), actual.text)
            assertEquals(id, expected.getInt("fieldEpoch"), actual.fieldEpoch)
            assertEquals(id, expected.getBoolean("activeReceipt"), actual.activeReceipt)
            assertEquals(id, expected.nullableString("receiptMode"), actual.receiptMode)
            assertEquals(id, expected.nullableString("receiptSource"), actual.receiptSource)
            assertEquals(id, expected.getBoolean("pendingLearning"), actual.pendingLearning)
            assertEquals(
                id,
                expected.getJSONArray("acceptedLearning").strings(),
                actual.acceptedLearning,
            )
            assertEquals(
                id,
                expected.getJSONArray("rejectedSources").strings(),
                actual.rejectedSources,
            )
            assertEquals(id, expected.getInt("ignoredEvents"), actual.ignoredEvents)
        }
    }

    @Test
    fun `interaction routing replays bundled shared contract`() {
        val suite = fixture("interaction-routing")
        assertEquals(1, suite.getInt("schemaVersion"))
        assertEquals(KeyboardCatalog.REVISION, suite.getString("catalogRevision"))
        val configuration = ContractInteractionConfiguration.from(
            suite.getJSONObject("configuration"),
        )

        suite.getJSONArray("cases").objects().forEach { case ->
            val id = case.getString("id")
            val actual = KotlinInteractionTraceReplayer.replay(
                configuration = configuration,
                events = case.getJSONArray("events"),
                caseId = id,
            )
            val expected = ContractInteractionOutcome.from(case.getJSONObject("expect"))
            assertEquals(id, expected, actual)
        }
    }

    @Test
    fun `timed swipe recognition replays bundled shared dwell contract`() {
        val suite = fixture("swipe-dwell")
        assertEquals(1, suite.getInt("schemaVersion"))
        assertEquals(KeyboardCatalog.REVISION, suite.getString("catalogRevision"))

        suite.getJSONArray("cases").objects().forEach { case ->
            val id = case.getString("id")
            val input = case.getJSONObject("input")
            val expected = case.getJSONObject("expect")
            val expectedWord = expected.getString("keySequence")
            val collapsedWord = expectedWord.collapseRepeatedRuns()
            val alternate = if (expectedWord == collapsedWord) {
                expectedWord.insertingDuplicate()
            } else {
                collapsedWord
            }
            val languageId = input.getString("languageId")
            val samples = input.getJSONArray("samples").objects().map { sample ->
                SwipePathSample(
                    x = sample.getDouble("x"),
                    y = sample.getDouble("y"),
                    timestampMilliseconds = sample.getDouble("atMilliseconds"),
                )
            }
            val result = SwipeTypingEngine(
                words = emptyList(),
                languageWords = mapOf(languageId to listOf(alternate, expectedWord)),
            ).recognize(
                samples = samples,
                limit = 2,
                languageTag = languageId,
            )

            assertEquals("$id: $result", expectedWord, result.acceptedCandidate?.word)
            assertEquals(
                id,
                expected.getJSONArray("repeatedRuns").strings(),
                result.acceptedCandidate?.word?.repeatedRuns(),
            )
            assertEquals(id, expectedWord, result.candidates.firstOrNull()?.word)
            assertTrue(
                "$id: expected alternate $alternate, got $result",
                result.candidates.drop(1).any { it.word == alternate },
            )
            assertFalse("$id: $result", result.abstained)
        }
    }

    @Test
    fun `Italian swipe recognition replays bundled shared display contract`() {
        val suite = fixture("swipe-recognition")
        assertEquals(1, suite.getInt("schemaVersion"))
        assertEquals(KeyboardCatalog.REVISION, suite.getString("catalogRevision"))

        suite.getJSONArray("cases").objects().forEach { case ->
            val id = case.getString("id")
            val input = case.getJSONObject("input")
            val expected = case.getJSONObject("expect")
            val languageId = input.getString("languageId")
            val vocabulary = input.getJSONArray("vocabulary").strings()
            val samples = input.getJSONArray("samples").objects().map { sample ->
                SwipePathSample(
                    x = sample.getDouble("x"),
                    y = sample.getDouble("y"),
                    timestampMilliseconds = sample.getDouble("atMilliseconds"),
                )
            }
            val result = SwipeTypingEngine(
                words = emptyList(),
                languageWords = mapOf(languageId to vocabulary),
            ).recognize(
                samples = samples,
                limit = vocabulary.size,
                languageTag = languageId,
            )

            assertEquals("$id: $result", expected.getString("displayWord"), result.acceptedCandidate?.word)
            assertEquals(id, expected.getString("displayWord"), result.candidates.firstOrNull()?.word)
            assertEquals(
                id,
                expected.getString("geometryKey"),
                SwipeWordNormalizer.normalize(expected.getString("displayWord"))?.geometry,
            )
            assertFalse("$id: $result", result.abstained)
        }
    }

    @Test
    fun `tap decoder replays bundled shared language and acceptance contract`() {
        val suite = fixture("tap-decoding")
        assertEquals(1, suite.getInt("schemaVersion"))
        assertEquals(KeyboardCatalog.REVISION, suite.getString("catalogRevision"))
        val decoder = TapWordDecoder(contractLexicon())

        suite.getJSONArray("cases").objects().forEach { case ->
            val id = case.getString("id")
            val input = case.getJSONObject("input")
            val expected = case.getJSONObject("expect")
            val taps = input.getJSONArray("taps").objects().map { tap ->
                TapWordLatticeTap(
                    literalKey = tap.getString("literalKey").single(),
                    resolvedKey = tap.getString("resolvedKey").single(),
                    candidates = tap.getJSONArray("candidates").objects().map { candidate ->
                        KeyCandidate(
                            character = candidate.getString("key").single(),
                            confidence = candidate.getDouble("confidence"),
                        )
                    },
                )
            }
            val result = decoder.decode(
                taps = taps,
                languageTag = input.getString("languageId"),
                limit = 5,
            )
            val candidateWords = result.candidates.map { it.word }
            val policy = TapWordAcceptancePolicy.valueOf(input.getString("policy").uppercase())
            val expectedAccepted = expected.nullableString("acceptedWord")

            assertEquals(id, expected.getString("literalWord"), result.literalWord)
            assertEquals(id, expected.getString("resolvedWord"), result.resolvedWord)
            assertEquals(id, expected.getString("topWord"), candidateWords.firstOrNull())
            assertEquals(id, expectedAccepted, policy.acceptedCandidate(result)?.word)
            expected.getJSONArray("containsWords").strings().forEach { word ->
                assertTrue("$id: missing $word in $candidateWords", word in candidateWords)
            }
            expected.getJSONArray("excludesWords").strings().forEach { word ->
                assertFalse("$id: unexpected $word in $candidateWords", word in candidateWords)
            }
        }
    }

    private fun fixture(name: String): JSONObject {
        val path = "keyboard-contract/$name.json"
        val stream = requireNotNull(javaClass.classLoader?.getResourceAsStream(path)) {
            "Missing bundled keyboard contract fixture $path"
        }
        return stream.bufferedReader(Charsets.UTF_8).use { JSONObject(it.readText()) }
    }
}

private fun String.editorFieldKind(): EditorFieldKind = when (this) {
    "text" -> EditorFieldKind.TEXT
    "multiline" -> EditorFieldKind.MULTILINE
    "literal" -> EditorFieldKind.LITERAL
    "name" -> EditorFieldKind.NAME
    "search" -> EditorFieldKind.SEARCH
    "email" -> EditorFieldKind.EMAIL
    "url" -> EditorFieldKind.URL
    "number" -> EditorFieldKind.NUMBER
    "decimal" -> EditorFieldKind.DECIMAL
    "phone" -> EditorFieldKind.PHONE
    "datetime" -> EditorFieldKind.DATETIME
    "code" -> EditorFieldKind.CODE
    "oneTimeCode" -> EditorFieldKind.ONE_TIME_CODE
    "password" -> EditorFieldKind.PASSWORD
    else -> error("Unknown shared keyboard field kind $this")
}

private fun CatalogFieldKind.layoutVariantId(): String = when (this) {
    CatalogFieldKind.EMAIL -> "email"
    CatalogFieldKind.URL -> "url"
    CatalogFieldKind.NUMBER, CatalogFieldKind.DATETIME -> "number"
    CatalogFieldKind.DECIMAL -> "decimal"
    CatalogFieldKind.PHONE -> "phone"
    CatalogFieldKind.SEARCH -> "search"
    CatalogFieldKind.LITERAL -> "literal"
    CatalogFieldKind.CODE -> "code"
    CatalogFieldKind.ONE_TIME_CODE, CatalogFieldKind.PASSWORD -> "secure"
    CatalogFieldKind.TEXT, CatalogFieldKind.MULTILINE, CatalogFieldKind.NAME -> "text"
}

private fun CapabilityDecision.contractCode(): String = when (denialReason) {
    null -> "allowed"
    CapabilityDenialReason.SENSITIVE_FIELD -> "denied.sensitive-field"
    CapabilityDenialReason.STRUCTURED_FIELD -> "denied.structured-field"
    CapabilityDenialReason.CODE_FIELD -> "denied.code-field"
    CapabilityDenialReason.EDITOR_DISABLED_ASSISTANCE -> "denied.editor-no-suggestions"
    CapabilityDenialReason.EDITOR_DISABLED_PERSONALIZED_LEARNING ->
        "denied.personalized-learning-disabled"
    CapabilityDenialReason.CLOUD_CONSENT_REQUIRED -> "denied.cloud-consent-required"
    CapabilityDenialReason.CLOUD_TRANSPORT_UNAVAILABLE ->
        "denied.cloud-transport-unavailable"
    CapabilityDenialReason.PLATFORM_VOICE_UNAVAILABLE ->
        "denied.platform-voice-unavailable"
    CapabilityDenialReason.EDITOR_CURSOR_UNAVAILABLE -> "denied.cursor-unavailable"
    CapabilityDenialReason.EDITOR_CONTEXT_UNAVAILABLE -> "denied.context-unavailable"
    CapabilityDenialReason.EDITOR_COMPOSITION_UNAVAILABLE ->
        "denied.composition-unavailable"
    CapabilityDenialReason.SHARED_TRANSCRIPT_UNAVAILABLE ->
        "denied.shared-container-unavailable"
}

private data class ContractCorrectionState(
    val text: String,
    val fieldEpoch: Int,
    val activeReceipt: Boolean,
    val receiptMode: String?,
    val receiptSource: String?,
    val pendingLearning: Boolean,
    val acceptedLearning: List<String>,
    val rejectedSources: List<String>,
    val ignoredEvents: Int,
)

private data class ContractInteractionConfiguration(
    val longPressDelayMilliseconds: Double,
    val swipeDistance: Double,
    val alternateStep: Double,
    val cursorActivationMilliseconds: Double,
    val cursorActivationDistance: Double,
    val cursorStep: Double,
    val deleteRepeatDelayMilliseconds: Double,
    val deleteRepeatIntervalMilliseconds: Double,
) {
    val native: KeyboardInteractionRouter.Configuration
        get() = KeyboardInteractionRouter.Configuration(
            longPressDelaySeconds = longPressDelayMilliseconds / 1_000.0,
            swipeDistance = swipeDistance,
            alternateStep = alternateStep,
            cursorActivationDelaySeconds = cursorActivationMilliseconds / 1_000.0,
            cursorActivationDistance = cursorActivationDistance,
            cursorStep = cursorStep,
            deleteRepeatDelaySeconds = deleteRepeatDelayMilliseconds / 1_000.0,
            deleteRepeatIntervalSeconds = deleteRepeatIntervalMilliseconds / 1_000.0,
            minimumDeleteRepeatIntervalSeconds = deleteRepeatIntervalMilliseconds / 1_000.0,
        )

    companion object {
        fun from(json: JSONObject) = ContractInteractionConfiguration(
            longPressDelayMilliseconds = json.getDouble("longPressDelayMilliseconds"),
            swipeDistance = json.getDouble("swipeDistance"),
            alternateStep = json.getDouble("alternateStep"),
            cursorActivationMilliseconds = json.getDouble("cursorActivationMilliseconds"),
            cursorActivationDistance = json.getDouble("cursorActivationDistance"),
            cursorStep = json.getDouble("cursorStep"),
            deleteRepeatDelayMilliseconds = json.getDouble("deleteRepeatDelayMilliseconds"),
            deleteRepeatIntervalMilliseconds = json.getDouble("deleteRepeatIntervalMilliseconds"),
        )
    }
}

private data class ContractInteractionOutcome(
    val committedText: List<String>,
    val deleteBackwardCount: Int,
    val deleteWordCount: Int,
    val cursorDeltas: List<Int>,
    val swipePhases: List<String>,
    val keyFeedbackCount: Int,
    val selectionFeedbackCount: Int,
    val alternateSelections: List<Int>,
    val hideAlternatesCount: Int,
    val settled: Boolean,
) {
    companion object {
        fun from(json: JSONObject) = ContractInteractionOutcome(
            committedText = json.getJSONArray("committedText").strings(),
            deleteBackwardCount = json.getInt("deleteBackwardCount"),
            deleteWordCount = json.getInt("deleteWordCount"),
            cursorDeltas = json.getJSONArray("cursorDeltas").ints(),
            swipePhases = json.getJSONArray("swipePhases").strings(),
            keyFeedbackCount = json.getInt("keyFeedbackCount"),
            selectionFeedbackCount = json.getInt("selectionFeedbackCount"),
            alternateSelections = json.getJSONArray("alternateSelections").ints(),
            hideAlternatesCount = json.getInt("hideAlternatesCount"),
            settled = json.getBoolean("settled"),
        )
    }
}

private class KotlinInteractionTraceReplayer private constructor(
    configuration: ContractInteractionConfiguration,
) {
    private val router = KeyboardInteractionRouter(configuration.native)
    private val projector = InteractionEffectProjector()
    private val scheduled = mutableMapOf<String, InteractionDeadline>()

    private fun consume(event: JSONObject, caseId: String) {
        val timeSeconds = event.getDouble("atMilliseconds") / 1_000.0
        val input = when (val kind = event.getString("kind")) {
            "pressKey" -> InteractionInput.Press(
                target = InteractionTarget.Key(
                    literal = event.getString("literal"),
                    alternates = event.getJSONArray("alternates").strings(),
                ),
                point = event.point(),
                timeSeconds = timeSeconds,
            )
            "pressSpace" -> InteractionInput.Press(
                InteractionTarget.Space,
                event.point(),
                timeSeconds,
            )
            "pressDelete" -> InteractionInput.Press(
                InteractionTarget.Delete,
                event.point(),
                timeSeconds,
            )
            "move" -> InteractionInput.Move(event.point(), timeSeconds)
            "release" -> InteractionInput.Release(event.point(), timeSeconds)
            "cancel" -> InteractionInput.Cancel
            "fireScheduled" -> {
                val deadlineKind = event.getString("deadlineKind")
                val deadline = requireNotNull(scheduled.remove(deadlineKind)) {
                    "$caseId: missing scheduled $deadlineKind deadline"
                }
                assertEquals(
                    "$caseId: $deadlineKind deadline",
                    timeSeconds,
                    deadline.dueTimeSeconds,
                    0.000_001,
                )
                InteractionInput.Deadline(deadline)
            }
            else -> error("$caseId: unknown interaction event $kind")
        }
        consume(router.handle(input))
    }

    private fun consume(effects: List<InteractionEffect>) {
        projector.consume(effects)
        effects.filterIsInstance<InteractionEffect.Schedule>().forEach { effect ->
            scheduled[effect.deadline.contractKey()] = effect.deadline
        }
    }

    companion object {
        fun replay(
            configuration: ContractInteractionConfiguration,
            events: JSONArray,
            caseId: String,
        ): ContractInteractionOutcome {
            val replayer = KotlinInteractionTraceReplayer(configuration)
            events.objects().forEach { replayer.consume(it, caseId) }
            return replayer.projector.outcome
        }
    }
}

private class InteractionEffectProjector {
    private val committedText = mutableListOf<String>()
    private var deleteBackwardCount = 0
    private var deleteWordCount = 0
    private val cursorDeltas = mutableListOf<Int>()
    private val swipePhases = mutableListOf<String>()
    private var keyFeedbackCount = 0
    private var selectionFeedbackCount = 0
    private val alternateSelections = mutableListOf<Int>()
    private var hideAlternatesCount = 0
    private var isPressed = false
    private var previewVisible = false
    private var alternatesVisible = false

    fun consume(effects: List<InteractionEffect>) {
        effects.forEach { effect ->
            when (effect) {
                is InteractionEffect.Pressed -> isPressed = effect.target != null
                is InteractionEffect.Preview -> previewVisible = effect.text != null
                is InteractionEffect.ShowAlternates -> {
                    alternatesVisible = true
                    alternateSelections += effect.selectedIndex
                }
                InteractionEffect.HideAlternates -> {
                    alternatesVisible = false
                    hideAlternatesCount += 1
                }
                is InteractionEffect.CommitText -> committedText += effect.text
                InteractionEffect.DeleteBackward -> deleteBackwardCount += 1
                InteractionEffect.DeleteWord -> deleteWordCount += 1
                is InteractionEffect.MoveCursor -> cursorDeltas += effect.characterDelta
                is InteractionEffect.SwipeBegan -> swipePhases += "began"
                is InteractionEffect.SwipeMoved -> swipePhases += "moved"
                is InteractionEffect.SwipeEnded -> swipePhases += "ended"
                is InteractionEffect.Feedback -> when (effect.kind) {
                    InteractionFeedback.KEY -> keyFeedbackCount += 1
                    InteractionFeedback.SELECTION -> selectionFeedbackCount += 1
                }
                is InteractionEffect.Schedule -> Unit
            }
        }
    }

    val outcome: ContractInteractionOutcome
        get() {
            return ContractInteractionOutcome(
                committedText = committedText.toList(),
                deleteBackwardCount = deleteBackwardCount,
                deleteWordCount = deleteWordCount,
                cursorDeltas = cursorDeltas.toList(),
                swipePhases = swipePhases.toList(),
                keyFeedbackCount = keyFeedbackCount,
                selectionFeedbackCount = selectionFeedbackCount,
                alternateSelections = alternateSelections.toList(),
                hideAlternatesCount = hideAlternatesCount,
                settled = !isPressed && !previewVisible && !alternatesVisible,
            )
        }
}

private fun InteractionDeadline.contractKey(): String = when (kind) {
    InteractionDeadline.Kind.LONG_PRESS -> "longPress"
    InteractionDeadline.Kind.CURSOR_ACTIVATION -> "cursorActivation"
    InteractionDeadline.Kind.DELETE_REPEAT -> "deleteRepeat"
}

private fun JSONObject.point() = InteractionPoint(
    x = getDouble("x"),
    y = getDouble("y"),
)

/** Thin JSON adapter over the production correction-session interface. */
private class CorrectionContractDriver private constructor(
    private val editor: CorrectionCompositionValueEditor,
    private val session: CorrectionCompositionSession,
) {
    private val acceptedLearning = mutableListOf<String>()
    private val rejectedSources = mutableListOf<String>()
    private var ignoredEvents = 0

    private val state: ContractCorrectionState
        get() {
            val snapshot = session.snapshot
            return ContractCorrectionState(
                text = editor.text,
                fieldEpoch = snapshot.fieldEpoch.toInt(),
                activeReceipt = snapshot.hasActiveReceipt,
                receiptMode = snapshot.receiptMode?.name?.lowercase(),
                receiptSource = snapshot.receiptSource,
                pendingLearning = snapshot.hasPendingLearning,
                acceptedLearning = acceptedLearning.toList(),
                rejectedSources = rejectedSources.toList(),
                ignoredEvents = ignoredEvents,
            )
        }

    private fun consume(event: JSONObject) {
        val effect = when (event.getString("kind")) {
            "applyAutomatic" -> applyAutomatic(event)
            "applyExplicit" -> applyExplicit(event)
            "applyAsyncAutomatic" -> applyAsyncAutomatic(event)
            "backspace" -> session.backspace(editor)
            "revert" -> session.visibleRevert(editor)
            "externalEdit" -> {
                editor.replaceTextExternally(event.nullableString("text") ?: editor.text)
                session.externalEditObserved()
                CorrectionCompositionEffect()
            }
            "changeField" -> {
                val nextEpoch = session.snapshot.fieldEpoch + 1
                session.changeField("field-$nextEpoch")
                editor.replaceTextExternally(event.nullableString("text").orEmpty())
                CorrectionCompositionEffect()
            }
            "advanceTime" -> session.advanceTime(
                event.getDouble("atMilliseconds").toLong(),
                editor,
            )
            else -> {
                ignoredEvents += 1
                return
            }
        }
        consume(effect)
    }

    private fun applyAutomatic(event: JSONObject): CorrectionCompositionEffect {
        val source = event.nullableString("source")
        val original = event.nullableString("original")
        val replacement = event.nullableString("replacement")
        if (source == null || original == null || replacement == null) {
            return CorrectionCompositionEffect(ignored = true)
        }
        val boundary = event.nullableString("boundary").orEmpty()
        val precedingContext = if (editor.text.endsWith(original)) {
            editor.text.dropLast(original.length)
        } else {
            ""
        }
        return session.applyAutomatic(
            editor = editor,
            originalText = original,
            replacementText = replacement,
            boundaryText = boundary,
            precedingContext = precedingContext,
            languageTag = "en",
            source = source,
            atMilliseconds = event.getDouble("atMilliseconds").toLong(),
            receiptLifetimeMilliseconds =
                event.optionalDouble("receiptLifetimeMilliseconds", 3_000.0).toLong(),
        )
    }

    private fun applyAsyncAutomatic(event: JSONObject): CorrectionCompositionEffect {
        val capturedFieldEpoch = event.optLong("capturedFieldEpoch", Long.MIN_VALUE)
        val source = event.nullableString("source")
        val original = event.nullableString("original")
        val replacement = event.nullableString("replacement")
        if (source == null || original == null || replacement == null) {
            return CorrectionCompositionEffect(ignored = true)
        }
        val boundary = event.nullableString("boundary").orEmpty()
        val precedingContext = if (editor.text.endsWith(original)) {
            editor.text.dropLast(original.length)
        } else {
            ""
        }
        return session.applyAsyncAutomatic(
            stamp = CorrectionCompositionAsyncStamp(
                fieldEpoch = capturedFieldEpoch,
                fieldIdentifier = session.snapshot.fieldIdentifier,
            ),
            editor = editor,
            originalText = original,
            replacementText = replacement,
            boundaryText = boundary,
            precedingContext = precedingContext,
            languageTag = "en",
            source = source,
            atMilliseconds = event.getDouble("atMilliseconds").toLong(),
            receiptLifetimeMilliseconds =
                event.optionalDouble("receiptLifetimeMilliseconds", 3_000.0).toLong(),
        )
    }

    private fun applyExplicit(event: JSONObject): CorrectionCompositionEffect {
        val source = event.nullableString("source")
        val original = event.nullableString("original")
        val replacement = event.nullableString("replacement")
        if (source == null || original == null || replacement == null) {
            return CorrectionCompositionEffect(ignored = true)
        }
        val precedingContext = if (editor.text.endsWith(original)) {
            editor.text.dropLast(original.length)
        } else {
            ""
        }
        return session.applyExplicit(
            editor = editor,
            originalText = original,
            replacementText = replacement,
            source = source,
            precedingContext = precedingContext,
            languageTag = "en",
            atMilliseconds = event.getDouble("atMilliseconds").toLong(),
            receiptLifetimeMilliseconds =
                event.optionalDouble("receiptLifetimeMilliseconds", 3_000.0).toLong(),
        )
    }

    private fun consume(effect: CorrectionCompositionEffect) {
        if (effect.ignored) ignoredEvents += 1
        effect.acceptedLearning?.let { acceptedLearning += it.text }
        effect.rejection?.let { rejectedSources += it.source }
    }

    companion object {
        fun replay(input: JSONObject, events: JSONArray): ContractCorrectionState {
            val initialEpoch = input.getLong("initialFieldEpoch")
            val driver = CorrectionContractDriver(
                editor = CorrectionCompositionValueEditor(input.getString("initialText")),
                session = CorrectionCompositionSession(
                    initialFieldEpoch = initialEpoch,
                    fieldIdentifier = "field-$initialEpoch",
                ),
            )
            events.objects().forEach(driver::consume)
            return driver.state
        }
    }
}

private fun String.collapseRepeatedRuns(): String = buildString {
    this@collapseRepeatedRuns.forEach { character ->
        if (lastOrNull() != character) append(character)
    }
}

private fun String.insertingDuplicate(): String = if (length < 2) {
    this
} else {
    substring(0, 1) + this[1] + substring(1)
}

private fun String.repeatedRuns(): List<String> {
    val result = mutableListOf<String>()
    var previous: Char? = null
    var count = 0
    forEach { character ->
        if (character == previous) {
            count += 1
        } else {
            if (previous != null && count > 1) result += previous.toString()
            previous = character
            count = 1
        }
    }
    if (previous != null && count > 1) result += previous.toString()
    return result
}

private fun JSONArray.objects(): List<JSONObject> =
    (0 until length()).map { index -> getJSONObject(index) }

private fun JSONArray.strings(): List<String> =
    (0 until length()).map { index -> getString(index) }

private fun JSONArray.ints(): List<Int> =
    (0 until length()).map { index -> getInt(index) }

private fun JSONObject.nullableString(key: String): String? =
    if (has(key) && !isNull(key)) getString(key) else null

private fun JSONObject.optionalDouble(key: String, fallback: Double): Double =
    if (has(key) && !isNull(key)) getDouble(key) else fallback
