import BuddyGrammarKit
import Testing

@Suite("Reviewable Buddy proposals")
struct ReviewableCorrectionProposalTests {
    @Test("proposal keeps original text until explicit acceptance")
    func proposalIsReviewable() {
        let proposal = ReviewableCorrectionProposal(
            intent: .shorten,
            originalText: "This is a very long sentence.",
            proposedText: "This sentence is long."
        )

        #expect(proposal.hasChanges)
        #expect(proposal.originalText == "This is a very long sentence.")
        #expect(proposal.proposedText == "This sentence is long.")
        #expect(proposal.change.originalChangedText == "is a very long sentence")
        #expect(proposal.change.proposedChangedText == "sentence is long")
    }

    @Test("identical cloud output is represented as no change")
    func noChange() {
        let proposal = ReviewableCorrectionProposal(
            intent: .fix,
            originalText: "Already correct.",
            proposedText: "Already correct."
        )

        #expect(!proposal.hasChanges)
        #expect(proposal.change.originalChangedText.isEmpty)
        #expect(proposal.change.proposedChangedText.isEmpty)
    }

    @Test("bounded diff keeps emoji and combining graphemes whole")
    func unicodeGraphemeDiff() {
        let family = "👨‍👩‍👧‍👦"
        let accented = "e\u{301}"
        let proposal = ReviewableCorrectionProposal(
            intent: .fix,
            originalText: "A\(family)\(accented) old",
            proposedText: "A\(family)\(accented) new"
        )

        #expect(proposal.change.commonPrefix == "A\(family)\(accented) ")
        #expect(proposal.change.originalChangedText == "old")
        #expect(proposal.change.proposedChangedText == "new")
    }

    @Test("changing one emoji keeps both changed spans whole")
    func changedEmojiDiff() {
        let proposal = ReviewableCorrectionProposal(
            intent: .friendly,
            originalText: "Mood 😀!",
            proposedText: "Mood 😁!"
        )

        #expect(proposal.change.commonPrefix == "Mood ")
        #expect(proposal.change.originalChangedText == "😀")
        #expect(proposal.change.proposedChangedText == "😁")
        #expect(proposal.change.commonSuffix == "!")
    }

    @Test("every intent contributes a bounded transformation instruction")
    func intentInstructions() {
        for intent in BuddyRewriteIntent.allCases {
            let instruction = intent.instruction(appendingTo: "Keep meaning.")
            #expect(instruction.hasPrefix("Keep meaning."))
            #expect(instruction.contains("Return only"))
        }
    }
}
