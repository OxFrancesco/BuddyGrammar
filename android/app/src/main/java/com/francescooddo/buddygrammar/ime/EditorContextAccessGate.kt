package com.francescooddo.buddygrammar.ime

/**
 * Lazy privacy boundary for host-editor text consumed by intelligence.
 * Denied capabilities never invoke [source], avoiding both content access and
 * an unnecessary InputConnection IPC round trip.
 */
internal object EditorContextAccessGate {
    fun <Value> read(
        capability: CapabilityDecision,
        source: () -> Value?,
    ): Value? {
        if (!capability.isAllowed) return null
        return source()
    }
}

/**
 * Routes a key to one—and only one—path after an adaptive context read.
 * A dynamic read failure must preserve the user's literal key press without
 * entering adaptive resolution or learning.
 */
internal object AdaptiveCharacterContextDispatch {
    fun dispatch(
        literalValue: String,
        contextBeforeCursor: String?,
        commitLiteral: (String) -> Unit,
        continueAdaptive: (String) -> Unit,
    ) {
        if (contextBeforeCursor == null) {
            commitLiteral(literalValue)
            return
        }
        continueAdaptive(contextBeforeCursor)
    }
}
