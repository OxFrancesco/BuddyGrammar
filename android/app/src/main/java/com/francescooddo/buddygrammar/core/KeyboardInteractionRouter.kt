package com.francescooddo.buddygrammar.core

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.roundToInt

data class InteractionPoint(
    val x: Double,
    val y: Double,
) {
    fun distanceTo(other: InteractionPoint): Double = hypot(x - other.x, y - other.y)

    companion object {
        val Zero = InteractionPoint(0.0, 0.0)
    }
}

sealed interface InteractionTarget {
    data class Key(
        val literal: String,
        val alternates: List<String> = emptyList(),
        val allowsSwipe: Boolean = true,
    ) : InteractionTarget

    data object Space : InteractionTarget
    data object Delete : InteractionTarget
}

enum class InteractionFeedback {
    KEY,
    SELECTION,
}

data class InteractionDeadline(
    val token: Int,
    val dueTimeSeconds: Double,
    val kind: Kind,
) {
    enum class Kind {
        LONG_PRESS,
        CURSOR_ACTIVATION,
        DELETE_REPEAT,
    }
}

sealed interface InteractionInput {
    data class Press(
        val target: InteractionTarget,
        val point: InteractionPoint,
        val timeSeconds: Double,
    ) : InteractionInput

    data class Move(
        val point: InteractionPoint,
        val timeSeconds: Double,
    ) : InteractionInput

    data class Release(
        val point: InteractionPoint,
        val timeSeconds: Double,
    ) : InteractionInput

    data class Deadline(val deadline: InteractionDeadline) : InteractionInput
    data object Cancel : InteractionInput
}

sealed interface InteractionEffect {
    data class Pressed(val target: InteractionTarget?) : InteractionEffect
    data class Preview(val text: String?) : InteractionEffect
    data class Schedule(val deadline: InteractionDeadline) : InteractionEffect
    data class ShowAlternates(
        val alternates: List<String>,
        val selectedIndex: Int,
    ) : InteractionEffect

    data object HideAlternates : InteractionEffect
    data class CommitText(val text: String) : InteractionEffect
    data object DeleteBackward : InteractionEffect
    data object DeleteWord : InteractionEffect
    data class MoveCursor(val characterDelta: Int) : InteractionEffect
    data class SwipeBegan(val point: InteractionPoint) : InteractionEffect
    data class SwipeMoved(val point: InteractionPoint) : InteractionEffect
    data class SwipeEnded(val point: InteractionPoint) : InteractionEffect
    data class Feedback(val kind: InteractionFeedback) : InteractionEffect
}

/**
 * Platform-neutral pointer interaction state machine.
 *
 * Scheduling and editor mutation stay in the native adapter. Deadlines carry a
 * generation token, so releasing, cancelling, or starting another key makes an
 * outstanding callback harmless.
 */
class KeyboardInteractionRouter(
    private val configuration: Configuration = KeyboardCatalog.gestures.routerConfiguration(),
) {
    data class Configuration(
        val longPressDelaySeconds: Double = 0.35,
        val swipeDistance: Double = 24.0,
        val alternateStep: Double = 26.0,
        val cursorActivationDelaySeconds: Double = 0.18,
        val cursorActivationDistance: Double = 12.0,
        val cursorStep: Double = 12.0,
        val deleteRepeatDelaySeconds: Double = 0.36,
        val deleteRepeatIntervalSeconds: Double = 0.07,
        val minimumDeleteRepeatIntervalSeconds: Double = 0.07,
    )

    private sealed interface ActiveState {
        data class Key(
            val token: Int,
            val literal: String,
            val alternates: List<String>,
            val origin: InteractionPoint,
            val allowsSwipe: Boolean,
            val isSwiping: Boolean = false,
            val alternatesVisible: Boolean = false,
            val alternateIndex: Int = 0,
        ) : ActiveState

        data class Space(
            val token: Int,
            val origin: InteractionPoint,
            val cursorMode: Boolean = false,
            val emittedCursorSteps: Int = 0,
        ) : ActiveState

        data class Delete(
            val token: Int,
            val repeatCount: Int = 0,
        ) : ActiveState
    }

    private var nextToken = 0
    private var active: ActiveState? = null

    fun handle(input: InteractionInput): List<InteractionEffect> = when (input) {
        is InteractionInput.Press -> begin(input)
        is InteractionInput.Move -> move(input.point, input.timeSeconds)
        is InteractionInput.Release -> release(input.point)
        is InteractionInput.Deadline -> fire(input.deadline)
        InteractionInput.Cancel -> cancel()
    }

    private fun begin(input: InteractionInput.Press): List<InteractionEffect> {
        nextToken += 1
        val token = nextToken
        return when (val target = input.target) {
            is InteractionTarget.Key -> {
                active = ActiveState.Key(
                    token = token,
                    literal = target.literal,
                    alternates = target.alternates,
                    origin = input.point,
                    allowsSwipe = target.allowsSwipe,
                )
                buildList {
                    add(InteractionEffect.Pressed(target))
                    add(InteractionEffect.Preview(target.literal))
                    if (target.alternates.isNotEmpty()) {
                        add(
                            InteractionEffect.Schedule(
                                InteractionDeadline(
                                    token = token,
                                    dueTimeSeconds = input.timeSeconds +
                                        configuration.longPressDelaySeconds.coerceAtLeast(0.0),
                                    kind = InteractionDeadline.Kind.LONG_PRESS,
                                ),
                            ),
                        )
                    }
                    add(InteractionEffect.Feedback(InteractionFeedback.KEY))
                }
            }

            InteractionTarget.Space -> {
                active = ActiveState.Space(
                    token = token,
                    origin = input.point,
                )
                listOf(
                    InteractionEffect.Pressed(InteractionTarget.Space),
                    InteractionEffect.Schedule(
                        InteractionDeadline(
                            token = token,
                            dueTimeSeconds = input.timeSeconds +
                                configuration.cursorActivationDelaySeconds.coerceAtLeast(0.0),
                            kind = InteractionDeadline.Kind.CURSOR_ACTIVATION,
                        ),
                    ),
                    InteractionEffect.Feedback(InteractionFeedback.KEY),
                )
            }

            InteractionTarget.Delete -> {
                active = ActiveState.Delete(token = token)
                listOf(
                    InteractionEffect.Pressed(InteractionTarget.Delete),
                    InteractionEffect.DeleteBackward,
                    InteractionEffect.Feedback(InteractionFeedback.KEY),
                    InteractionEffect.Schedule(
                        InteractionDeadline(
                            token = token,
                            dueTimeSeconds = input.timeSeconds +
                                configuration.deleteRepeatDelaySeconds.coerceAtLeast(0.0),
                            kind = InteractionDeadline.Kind.DELETE_REPEAT,
                        ),
                    ),
                )
            }
        }
    }

    private fun move(
        point: InteractionPoint,
        _timeSeconds: Double,
    ): List<InteractionEffect> = when (val state = active) {
        is ActiveState.Key -> when {
            state.alternatesVisible -> {
                val rawIndex = ((point.x - state.origin.x) /
                    configuration.alternateStep.coerceAtLeast(1.0)).roundToInt()
                val index = rawIndex.coerceIn(0, state.alternates.lastIndex)
                if (index == state.alternateIndex) {
                    emptyList()
                } else {
                    active = state.copy(alternateIndex = index)
                    listOf(InteractionEffect.ShowAlternates(state.alternates, index))
                }
            }

            state.isSwiping -> listOf(InteractionEffect.SwipeMoved(point))
            state.allowsSwipe &&
                state.origin.distanceTo(point) >= configuration.swipeDistance.coerceAtLeast(1.0) -> {
                active = state.copy(isSwiping = true)
                listOf(
                    InteractionEffect.Preview(null),
                    InteractionEffect.SwipeBegan(state.origin),
                    InteractionEffect.SwipeMoved(point),
                )
            }

            else -> emptyList()
        }

        is ActiveState.Space -> {
            val horizontalDistance = point.x - state.origin.x
            if (!state.cursorMode &&
                abs(horizontalDistance) <
                configuration.cursorActivationDistance.coerceAtLeast(1.0)
            ) {
                emptyList()
            } else {
                val effects = mutableListOf<InteractionEffect>()
                if (!state.cursorMode) {
                    effects += InteractionEffect.Preview(null)
                    effects += InteractionEffect.Feedback(InteractionFeedback.SELECTION)
                }
                val totalSteps = (horizontalDistance /
                    configuration.cursorStep.coerceAtLeast(1.0)).toInt()
                val delta = totalSteps - state.emittedCursorSteps
                if (delta != 0) effects += InteractionEffect.MoveCursor(delta)
                active = state.copy(
                    cursorMode = true,
                    emittedCursorSteps = totalSteps,
                )
                effects
            }
        }

        is ActiveState.Delete, null -> emptyList()
    }

    private fun release(point: InteractionPoint): List<InteractionEffect> {
        val released = active
        active = null
        return when (released) {
            is ActiveState.Key -> when {
                released.isSwiping -> listOf(
                    InteractionEffect.SwipeEnded(point),
                    InteractionEffect.Pressed(null),
                )

                released.alternatesVisible -> listOf(
                    InteractionEffect.CommitText(released.alternates[released.alternateIndex]),
                    InteractionEffect.HideAlternates,
                    InteractionEffect.Preview(null),
                    InteractionEffect.Pressed(null),
                )

                else -> listOf(
                    InteractionEffect.CommitText(released.literal),
                    InteractionEffect.Preview(null),
                    InteractionEffect.Pressed(null),
                )
            }

            is ActiveState.Space -> if (released.cursorMode) {
                listOf(InteractionEffect.Pressed(null))
            } else {
                listOf(
                    InteractionEffect.CommitText(" "),
                    InteractionEffect.Pressed(null),
                )
            }

            is ActiveState.Delete -> listOf(InteractionEffect.Pressed(null))
            null -> emptyList()
        }
    }

    private fun fire(deadline: InteractionDeadline): List<InteractionEffect> =
        when (val state = active) {
            is ActiveState.Key -> if (
                deadline.kind == InteractionDeadline.Kind.LONG_PRESS &&
                deadline.token == state.token &&
                !state.isSwiping &&
                !state.alternatesVisible &&
                state.alternates.isNotEmpty()
            ) {
                active = state.copy(alternatesVisible = true, alternateIndex = 0)
                listOf(
                    InteractionEffect.ShowAlternates(state.alternates, 0),
                    InteractionEffect.Feedback(InteractionFeedback.SELECTION),
                )
            } else {
                emptyList()
            }

            is ActiveState.Delete -> if (
                deadline.kind == InteractionDeadline.Kind.DELETE_REPEAT &&
                deadline.token == state.token
            ) {
                val effect = InteractionEffect.DeleteBackward
                val updated = state.copy(repeatCount = state.repeatCount + 1)
                active = updated
                val baseInterval = configuration.deleteRepeatIntervalSeconds.coerceAtLeast(0.01)
                val minimumInterval = configuration.minimumDeleteRepeatIntervalSeconds
                    .coerceIn(0.01, baseInterval)
                val acceleration = (updated.repeatCount * 0.01)
                    .coerceAtMost(baseInterval - minimumInterval)
                listOf(
                    effect,
                    InteractionEffect.Feedback(InteractionFeedback.KEY),
                    InteractionEffect.Schedule(
                        InteractionDeadline(
                            token = updated.token,
                            dueTimeSeconds = deadline.dueTimeSeconds + baseInterval - acceleration,
                            kind = InteractionDeadline.Kind.DELETE_REPEAT,
                        ),
                    ),
                )
            } else {
                emptyList()
            }

            is ActiveState.Space -> if (
                deadline.kind == InteractionDeadline.Kind.CURSOR_ACTIVATION &&
                deadline.token == state.token &&
                !state.cursorMode
            ) {
                active = state.copy(cursorMode = true)
                listOf(
                    InteractionEffect.Preview(null),
                    InteractionEffect.Feedback(InteractionFeedback.SELECTION),
                )
            } else {
                emptyList()
            }

            null -> emptyList()
        }

    private fun cancel(): List<InteractionEffect> {
        val cancelled = active ?: return emptyList()
        active = null
        return when (cancelled) {
            is ActiveState.Key -> if (cancelled.alternatesVisible) {
                listOf(
                    InteractionEffect.HideAlternates,
                    InteractionEffect.Preview(null),
                    InteractionEffect.Pressed(null),
                )
            } else {
                listOf(InteractionEffect.Preview(null), InteractionEffect.Pressed(null))
            }

            is ActiveState.Space, is ActiveState.Delete ->
                listOf(InteractionEffect.Pressed(null))
        }
    }
}
