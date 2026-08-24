package com.francescooddo.buddygrammar.ime

/**
 * Monotonic ownership token for asynchronous correction requests.
 *
 * Android cancellation is cooperative, so an older coroutine can reach its
 * `finally` block after a replacement request has started. Only the current
 * token may publish results or clear shared request state.
 */
internal class CorrectionRequestOwnership {
    private var generation = 0L
    private var activeRequest: Long? = null

    fun begin(): Long = (++generation).also { activeRequest = it }

    fun isOwner(request: Long): Boolean = activeRequest == request

    fun finish(request: Long): Boolean {
        if (!isOwner(request)) return false
        activeRequest = null
        return true
    }

    fun cancel() {
        activeRequest = null
    }
}

internal object CorrectionLifecyclePolicy {
    fun selectionInvalidates(
        oldStart: Int,
        oldEnd: Int,
        newStart: Int,
        newEnd: Int,
    ): Boolean = oldStart != newStart || oldEnd != newEnd
}
