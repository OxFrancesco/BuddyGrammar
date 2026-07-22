package com.francescooddo.buddygrammar.ime

internal data class HandwritingWorkStamp(
    val fieldEpoch: Long,
    val inputRevision: Long,
    val requestIdentity: Long,
)

/** Field + stroke + request ownership for local and cloud recognition work. */
internal class HandwritingRequestOwnership(initialFieldEpoch: Long = 0) {
    var fieldEpoch: Long = initialFieldEpoch
        private set
    var inputRevision: Long = 0
        private set
    private var nextRequestIdentity = 0L
    private var active: HandwritingWorkStamp? = null

    fun changeField(newFieldEpoch: Long) {
        if (newFieldEpoch == fieldEpoch) return
        fieldEpoch = newFieldEpoch
        inputChanged()
    }

    fun inputChanged() {
        inputRevision += 1
        active = null
    }

    fun begin(): HandwritingWorkStamp {
        nextRequestIdentity += 1
        return HandwritingWorkStamp(
            fieldEpoch = fieldEpoch,
            inputRevision = inputRevision,
            requestIdentity = nextRequestIdentity,
        ).also { active = it }
    }

    fun isOwner(stamp: HandwritingWorkStamp): Boolean =
        active == stamp && isCurrent(stamp)

    fun isCurrent(stamp: HandwritingWorkStamp): Boolean =
        stamp.fieldEpoch == fieldEpoch &&
            stamp.inputRevision == inputRevision

    fun finish(stamp: HandwritingWorkStamp): Boolean {
        if (!isOwner(stamp)) return false
        active = null
        return true
    }
}
