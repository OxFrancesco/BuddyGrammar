package com.francescooddo.buddygrammar.ime

import com.francescooddo.buddygrammar.core.InteractionDeadline
import com.francescooddo.buddygrammar.core.InteractionPoint
import com.francescooddo.buddygrammar.core.KeyboardInteractionSession
import com.francescooddo.buddygrammar.core.KeyboardInteractionUpdate
import com.francescooddo.buddygrammar.core.KeyboardInteractionVisualState
import com.francescooddo.buddygrammar.core.KeyboardPointerBinding
import com.francescooddo.buddygrammar.core.SinglePointerInteractionOwner

/**
 * Pointer-ownership seam between Compose gestures and the shared single-pointer
 * interaction session. Returning `null` means the event came from a non-owner.
 */
internal class KeyboardPointerSessionAdapter<PointerToken : Any>(
    private val session: KeyboardInteractionSession = KeyboardInteractionSession(),
) {
    private val owner = SinglePointerInteractionOwner<PointerToken>()

    val visualState: KeyboardInteractionVisualState
        get() = session.visualState

    fun press(
        pointerToken: PointerToken,
        binding: KeyboardPointerBinding,
        point: InteractionPoint,
        timeSeconds: Double,
    ): KeyboardInteractionUpdate? {
        if (!owner.acquire(pointerToken)) return null
        return session.press(binding, point, timeSeconds)
    }

    fun move(
        pointerToken: PointerToken,
        point: InteractionPoint,
        timeSeconds: Double,
    ): KeyboardInteractionUpdate? {
        if (!owner.owns(pointerToken)) return null
        return session.move(point, timeSeconds)
    }

    fun release(
        pointerToken: PointerToken,
        point: InteractionPoint,
        timeSeconds: Double,
    ): KeyboardInteractionUpdate? {
        if (!owner.owns(pointerToken)) return null
        return try {
            session.release(point, timeSeconds)
        } finally {
            owner.release(pointerToken)
        }
    }

    fun cancel(pointerToken: PointerToken): KeyboardInteractionUpdate? {
        if (!owner.owns(pointerToken)) return null
        owner.release(pointerToken)
        return session.cancel()
    }

    fun deadline(deadline: InteractionDeadline): KeyboardInteractionUpdate =
        session.deadline(deadline)

    fun cancelActive(): KeyboardInteractionUpdate {
        owner.reset()
        return session.cancel()
    }
}
