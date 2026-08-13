package com.francescooddo.buddygrammar.ime

import android.os.Build
import android.os.SystemClock
import android.media.AudioManager
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import com.francescooddo.buddygrammar.core.InteractionCommand
import com.francescooddo.buddygrammar.core.InteractionFeedback
import com.francescooddo.buddygrammar.core.InteractionPoint
import com.francescooddo.buddygrammar.core.KeyboardInteractionSession
import com.francescooddo.buddygrammar.core.KeyboardInteractionUpdate
import com.francescooddo.buddygrammar.core.KeyboardFeedbackPolicy
import com.francescooddo.buddygrammar.core.KeyboardLatencyMetric
import com.francescooddo.buddygrammar.core.KeyboardLatencyRecorder
import com.francescooddo.buddygrammar.core.KeyboardLatencyToken
import com.francescooddo.buddygrammar.core.KeyboardPointerBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToLong

internal class KeyboardInteractionComposeAdapter(
    private val service: BuddyGrammarImeService,
    private val scope: CoroutineScope,
    private val feedbackView: View,
    private val nowSeconds: () -> Double = { SystemClock.uptimeMillis() / 1_000.0 },
    private val session: KeyboardInteractionSession = KeyboardInteractionSession(),
    private val latencyRecorder: KeyboardLatencyRecorder = KeyboardLatencyRecorder.production,
) {
    private val pointerSession = KeyboardPointerSessionAdapter<PointerId>(session)
    private val audioManager = feedbackView.context.getSystemService(AudioManager::class.java)
    private val systemSoundEffectsEnabled = Settings.System.getInt(
        feedbackView.context.contentResolver,
        Settings.System.SOUND_EFFECTS_ENABLED,
        0,
    ) != 0

    var visualState by mutableStateOf(pointerSession.visualState)
        private set

    private var feedbackLatencyToken: KeyboardLatencyToken? = null
    private var commitLatencyToken: KeyboardLatencyToken? = null

    fun press(
        pointerId: PointerId,
        binding: KeyboardPointerBinding,
        position: Offset,
    ): Boolean {
        val pendingFeedbackToken = latencyRecorder.begin(KeyboardLatencyMetric.KEY_DOWN_TO_FEEDBACK)
        val pendingCommitToken = latencyRecorder.begin(KeyboardLatencyMetric.KEY_DOWN_TO_COMMIT)
        val update = pointerSession.press(
            pointerId,
            binding,
            position.interactionPoint(),
            nowSeconds(),
        )
        if (update == null) {
            latencyRecorder.cancel(pendingFeedbackToken)
            latencyRecorder.cancel(pendingCommitToken)
            return false
        }
        cancelActiveLatencyMeasurements()
        feedbackLatencyToken = pendingFeedbackToken
        commitLatencyToken = pendingCommitToken
        accept(update)
        return true
    }

    fun move(pointerId: PointerId, position: Offset): Boolean {
        val update = pointerSession.move(
            pointerId,
            position.interactionPoint(),
            nowSeconds(),
        ) ?: return false
        accept(update)
        return true
    }

    fun release(pointerId: PointerId, position: Offset): Boolean {
        val update = pointerSession.release(
            pointerId,
            position.interactionPoint(),
            nowSeconds(),
        ) ?: return false
        accept(update)
        cancelActiveLatencyMeasurements()
        return true
    }

    fun cancel(pointerId: PointerId): Boolean {
        val update = pointerSession.cancel(pointerId) ?: return false
        accept(update)
        cancelActiveLatencyMeasurements()
        return true
    }

    fun cancelActiveInteraction() {
        accept(pointerSession.cancelActive())
        cancelActiveLatencyMeasurements()
    }

    private fun accept(update: KeyboardInteractionUpdate) {
        visualState = update.visualState
        update.commands.forEach { command ->
            when (command) {
                is InteractionCommand.Schedule -> {
                    scope.launch {
                        val waitMillis = ((command.deadline.dueTimeSeconds - nowSeconds()) * 1_000.0)
                            .roundToLong()
                            .coerceAtLeast(0L)
                        delay(waitMillis)
                        accept(pointerSession.deadline(command.deadline))
                    }
                }
                is InteractionCommand.CommitAdaptiveKey -> recordCommitDispatch {
                    service.onAdaptiveCharacterKey(
                        value = command.text,
                        x = command.point.x,
                        y = command.point.y,
                    )
                }
                is InteractionCommand.CommitLiteralText -> recordCommitDispatch {
                    service.onCharacterKey(command.text)
                }
                InteractionCommand.CommitSpace -> recordCommitDispatch(service::onSpaceKey)
                InteractionCommand.DeleteBackward -> recordCommitDispatch(service::onDeleteKey)
                InteractionCommand.DeleteWord -> recordCommitDispatch(service::onDeleteWordKey)
                is InteractionCommand.MoveCursor -> service.moveCursorBy(command.characterDelta)
                is InteractionCommand.CommitSwipe -> {
                    cancelCommitLatencyMeasurement()
                    service.commitSwipe(command.samples)
                }
                is InteractionCommand.Feedback -> performFeedback(command.kind)
            }
        }
    }

    private fun performFeedback(kind: InteractionFeedback) {
        val constant = when (kind) {
            InteractionFeedback.KEY -> HapticFeedbackConstants.KEYBOARD_TAP
            InteractionFeedback.SELECTION -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                HapticFeedbackConstants.TEXT_HANDLE_MOVE
            } else {
                HapticFeedbackConstants.CLOCK_TICK
            }
        }
        feedbackView.performHapticFeedback(constant)
        if (
            audioManager != null && KeyboardFeedbackPolicy.shouldPlayStandardClick(
                feedback = kind,
                systemSoundEffectsEnabled = systemSoundEffectsEnabled,
                ringerModeNormal = audioManager.ringerMode == AudioManager.RINGER_MODE_NORMAL,
            )
        ) {
            audioManager.playSoundEffect(AudioManager.FX_KEYPRESS_STANDARD)
        }
        feedbackLatencyToken?.let(latencyRecorder::finish)
        feedbackLatencyToken = null
    }

    private inline fun recordCommitDispatch(operation: () -> Unit) {
        try {
            operation()
        } finally {
            commitLatencyToken?.let(latencyRecorder::finish)
            commitLatencyToken = null
        }
    }

    private fun cancelCommitLatencyMeasurement() {
        commitLatencyToken?.let(latencyRecorder::cancel)
        commitLatencyToken = null
    }

    private fun cancelActiveLatencyMeasurements() {
        feedbackLatencyToken?.let(latencyRecorder::cancel)
        feedbackLatencyToken = null
        cancelCommitLatencyMeasurement()
    }

    private fun Offset.interactionPoint(): InteractionPoint =
        InteractionPoint(x.toDouble(), y.toDouble())
}

@Composable
internal fun rememberKeyboardInteractionAdapter(
    service: BuddyGrammarImeService,
): KeyboardInteractionComposeAdapter {
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val adapter = remember(service, scope, view) {
        KeyboardInteractionComposeAdapter(service, scope, view)
    }
    DisposableEffect(adapter) {
        onDispose(adapter::cancelActiveInteraction)
    }
    return adapter
}

internal fun Modifier.routedKeyboardPointer(
    interactionKey: Any?,
    adapter: KeyboardInteractionComposeAdapter,
    binding: (width: Double, height: Double) -> KeyboardPointerBinding,
): Modifier = pointerInput(interactionKey, adapter) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        val resolvedBinding = binding(
            size.width.coerceAtLeast(1).toDouble(),
            size.height.coerceAtLeast(1).toDouble(),
        )
        var completed = false
        val acquired = adapter.press(down.id, resolvedBinding, down.position)
        if (!acquired) return@awaitEachGesture
        down.consume()
        try {
            while (true) {
                val event = awaitPointerEvent()
                val change = event.changes.firstOrNull { it.id == down.id }
                if (change == null) break
                change.consume()
                if (change.pressed) {
                    adapter.move(down.id, change.position)
                } else {
                    adapter.release(down.id, change.position)
                    completed = true
                    break
                }
            }
        } finally {
            if (!completed) adapter.cancel(down.id)
        }
    }
}
