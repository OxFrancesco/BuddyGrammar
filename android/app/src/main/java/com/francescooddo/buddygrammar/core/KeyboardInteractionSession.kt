package com.francescooddo.buddygrammar.core

data class KeySpaceTransform(
    val centerX: Double,
    val centerY: Double,
    val width: Double,
    val height: Double,
) {
    init {
        require(width > 0.0 && height > 0.0) { "Key geometry must have positive dimensions." }
    }

    fun map(point: InteractionPoint): SwipePoint = SwipePoint(
        x = centerX + point.x / width - 0.5,
        y = centerY + point.y / height - 0.5,
    )
}

sealed interface KeyboardPointerBinding {
    val target: InteractionTarget

    data class Letter(
        override val target: InteractionTarget.Key,
        val transform: KeySpaceTransform,
        val swipeTransform: KeySpaceTransform = transform,
    ) : KeyboardPointerBinding

    data class Space(
        val cursorMovementEnabled: Boolean,
    ) : KeyboardPointerBinding {
        override val target: InteractionTarget = InteractionTarget.Space
    }

    data object Delete : KeyboardPointerBinding {
        override val target: InteractionTarget = InteractionTarget.Delete
    }
}

data class KeyboardInteractionVisualState(
    val pressedTarget: InteractionTarget? = null,
    val previewText: String? = null,
    val alternates: List<String>? = null,
    val selectedAlternateIndex: Int = 0,
)

sealed interface InteractionCommand {
    data class Schedule(val deadline: InteractionDeadline) : InteractionCommand
    data class CommitAdaptiveKey(
        val text: String,
        val point: SwipePoint,
    ) : InteractionCommand

    data class CommitLiteralText(val text: String) : InteractionCommand
    data object CommitSpace : InteractionCommand
    data object DeleteBackward : InteractionCommand
    data object DeleteWord : InteractionCommand
    data class MoveCursor(val characterDelta: Int) : InteractionCommand
    data class CommitSwipe(val samples: List<SwipePathSample>) : InteractionCommand
    data class Feedback(val kind: InteractionFeedback) : InteractionCommand
}

data class KeyboardInteractionUpdate(
    val visualState: KeyboardInteractionVisualState,
    val commands: List<InteractionCommand>,
)

/**
 * Pure adapter between pointer-level router effects and native keyboard
 * commands. Compose owns deadlines and rendering; the IME owns mutations.
 */
class KeyboardInteractionSession(
    private val router: KeyboardInteractionRouter = KeyboardInteractionRouter(),
) {
    var visualState = KeyboardInteractionVisualState()
        private set

    private var activeBinding: KeyboardPointerBinding? = null
    private var gestureStartTimeSeconds: Double? = null
    private val swipeSamples = mutableListOf<SwipePathSample>()

    fun press(
        binding: KeyboardPointerBinding,
        point: InteractionPoint,
        timeSeconds: Double,
    ): KeyboardInteractionUpdate {
        activeBinding = binding
        gestureStartTimeSeconds = timeSeconds
        swipeSamples.clear()
        return apply(
            router.handle(InteractionInput.Press(binding.target, point, timeSeconds)),
            eventPoint = point,
            eventTimeSeconds = timeSeconds,
        )
    }

    fun move(point: InteractionPoint, timeSeconds: Double): KeyboardInteractionUpdate {
        val binding = activeBinding
        if (binding is KeyboardPointerBinding.Space && !binding.cursorMovementEnabled) {
            return KeyboardInteractionUpdate(visualState, emptyList())
        }
        return apply(
            router.handle(InteractionInput.Move(point, timeSeconds)),
            eventPoint = point,
            eventTimeSeconds = timeSeconds,
        )
    }

    fun release(point: InteractionPoint, timeSeconds: Double): KeyboardInteractionUpdate {
        val update = apply(
            router.handle(InteractionInput.Release(point, timeSeconds)),
            eventPoint = point,
            eventTimeSeconds = timeSeconds,
        )
        activeBinding = null
        gestureStartTimeSeconds = null
        swipeSamples.clear()
        return update
    }

    fun deadline(deadline: InteractionDeadline): KeyboardInteractionUpdate {
        val binding = activeBinding
        if (
            binding is KeyboardPointerBinding.Space &&
            !binding.cursorMovementEnabled &&
            deadline.kind == InteractionDeadline.Kind.CURSOR_ACTIVATION
        ) {
            return KeyboardInteractionUpdate(visualState, emptyList())
        }
        return apply(router.handle(InteractionInput.Deadline(deadline)))
    }

    fun cancel(): KeyboardInteractionUpdate {
        val update = apply(router.handle(InteractionInput.Cancel))
        activeBinding = null
        gestureStartTimeSeconds = null
        swipeSamples.clear()
        return update
    }

    private fun apply(
        effects: List<InteractionEffect>,
        eventPoint: InteractionPoint? = null,
        eventTimeSeconds: Double? = null,
    ): KeyboardInteractionUpdate {
        val commands = mutableListOf<InteractionCommand>()
        effects.forEach { effect ->
            when (effect) {
                is InteractionEffect.Pressed -> {
                    visualState = visualState.copy(pressedTarget = effect.target)
                }
                is InteractionEffect.Preview -> {
                    visualState = visualState.copy(previewText = effect.text)
                }
                is InteractionEffect.Schedule -> {
                    commands += InteractionCommand.Schedule(effect.deadline)
                }
                is InteractionEffect.ShowAlternates -> {
                    visualState = visualState.copy(
                        alternates = effect.alternates,
                        selectedAlternateIndex = effect.selectedIndex,
                    )
                }
                InteractionEffect.HideAlternates -> {
                    visualState = visualState.copy(alternates = null, selectedAlternateIndex = 0)
                }
                is InteractionEffect.CommitText -> {
                    commands += commitCommand(effect.text, eventPoint ?: InteractionPoint.Zero)
                }
                InteractionEffect.DeleteBackward -> commands += InteractionCommand.DeleteBackward
                InteractionEffect.DeleteWord -> commands += InteractionCommand.DeleteWord
                is InteractionEffect.MoveCursor -> {
                    commands += InteractionCommand.MoveCursor(effect.characterDelta)
                }
                is InteractionEffect.SwipeBegan -> addSwipeSample(
                    effect.point,
                    gestureStartTimeSeconds ?: eventTimeSeconds ?: 0.0,
                )
                is InteractionEffect.SwipeMoved -> addSwipeSample(
                    effect.point,
                    eventTimeSeconds ?: gestureStartTimeSeconds ?: 0.0,
                )
                is InteractionEffect.SwipeEnded -> {
                    addSwipeSample(
                        effect.point,
                        eventTimeSeconds ?: gestureStartTimeSeconds ?: 0.0,
                    )
                    if (swipeSamples.size >= 2) {
                        commands += InteractionCommand.CommitSwipe(swipeSamples.toList())
                    }
                }
                is InteractionEffect.Feedback -> {
                    commands += InteractionCommand.Feedback(effect.kind)
                }
            }
        }
        return KeyboardInteractionUpdate(visualState, commands)
    }

    private fun commitCommand(
        text: String,
        point: InteractionPoint,
    ): InteractionCommand = when (val binding = activeBinding) {
        is KeyboardPointerBinding.Letter -> if (text == binding.target.literal) {
            InteractionCommand.CommitAdaptiveKey(text, binding.transform.map(point))
        } else {
            InteractionCommand.CommitLiteralText(text)
        }
        is KeyboardPointerBinding.Space -> InteractionCommand.CommitSpace
        KeyboardPointerBinding.Delete, null -> InteractionCommand.CommitLiteralText(text)
    }

    private fun addSwipeSample(point: InteractionPoint, timeSeconds: Double) {
        val binding = activeBinding as? KeyboardPointerBinding.Letter ?: return
        val mapped = binding.swipeTransform.map(point)
        val timestampMilliseconds = (timeSeconds * 1_000.0)
            .coerceAtLeast(swipeSamples.lastOrNull()?.timestampMilliseconds ?: 0.0)
        swipeSamples += SwipePathSample(
            x = mapped.x,
            y = mapped.y,
            timestampMilliseconds = timestampMilliseconds,
        )
        if (swipeSamples.size > MAX_SWIPE_SAMPLES) {
            val first = swipeSamples.first()
            val last = swipeSamples.last()
            val compacted = buildList {
                add(first)
                var index = 1
                while (index < swipeSamples.lastIndex) {
                    add(swipeSamples[index])
                    index += 2
                }
                add(last)
            }
            swipeSamples.clear()
            swipeSamples += compacted
        }
    }

    private companion object {
        const val MAX_SWIPE_SAMPLES = 256
    }
}
