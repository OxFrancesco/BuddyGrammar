package com.francescooddo.buddygrammar.core

enum class CorrectionProposalScope(val displayName: String) {
    SELECTION("Selection"),
    CURRENT_SENTENCE("Current sentence"),
}

/** Exact editor observation captured before a cloud rewrite request starts. */
data class CorrectionProposalEditorStamp(
    val fieldEpoch: Long,
    val selectedText: String?,
    val textBeforeCursor: String,
    val textAfterCursor: String,
)

/** Review-only cloud result; editor mutation is possible only while [stamp] is fresh. */
data class CorrectionProposalTransaction(
    val proposal: ReviewableCorrectionProposal,
    val scope: CorrectionProposalScope,
    val stamp: CorrectionProposalEditorStamp,
    val cloudProcessed: Boolean = true,
) {
    init {
        require(proposal.hasChanges) { "A review transaction requires an actual text change." }
    }

    fun isFreshFor(observation: CorrectionProposalEditorStamp?): Boolean = observation == stamp

    fun replacementIfFresh(observation: CorrectionProposalEditorStamp?): String? =
        proposal.proposedText.takeIf { isFreshFor(observation) }
}
