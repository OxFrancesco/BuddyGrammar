import BuddyGrammarKit
import Foundation
import Testing

@Suite("Ranked swipe lexicons")
struct SwipeLexiconTests {
    @Test("comments and blank lines do not change rank order")
    func parsesRankedWords() throws {
        let words = try SwipeLexicon.parse(
            source: """
            # source metadata

            ciao
            grazie
            prego
            """
        )

        #expect(words == ["ciao", "grazie", "prego"])
    }

    @Test("Unicode spelling is preserved and apostrophes are canonicalized")
    func preservesDisplaySpelling() throws {
        let words = try SwipeLexicon.parse(
            source: "perché\ncaffè\nl'ho\npoʼ"
        )

        #expect(words == ["perché", "caffè", "l’ho", "po’"])
    }

    @Test("duplicate canonical spelling and non-word entries are rejected")
    func rejectsInvalidSources() {
        #expect(throws: SwipeLexiconError.duplicateEntry(line: 2, value: "ciao")) {
            try SwipeLexicon.parse(source: "ciao\nciao")
        }
        #expect(throws: SwipeLexiconError.duplicateEntry(line: 2, value: "l’ho")) {
            try SwipeLexicon.parse(source: "l'ho\nl’ho")
        }
        for malformed in ["due parole", "'aperto", "l''ho", "perché!", "È", "город"] {
            #expect(throws: SwipeLexiconError.self) {
                try SwipeLexicon.parse(source: malformed)
            }
        }
    }

    @Test("canonical accented entries have no legacy ASCII duplicate")
    func canonicalAssetHasNoMisspelledAlternates() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BuddyGrammarKit/Resources/SwipeVocabulary-it-v1.txt")
        let words = try SwipeLexicon.parse(
            source: String(contentsOf: sourceURL, encoding: .utf8)
        )
        for canonical in [
            "perché", "può", "già", "più", "però", "caffè", "città",
            "l’ho", "po’", "francesco", "giulia", "meeting", "feedback",
            "deadline", "whatsapp",
        ] {
            #expect(words.contains(canonical), "Missing \(canonical)")
        }
        for misspelling in [
            "perche", "puo", "gia", "piu", "pero", "cioe", "cosi",
            "lunedi", "martedi", "mercoledi", "giovedi", "venerdi",
            "papa", "universita", "attivita", "societa", "caffe", "menu", "citta",
        ] {
            #expect(!words.contains(misspelling), "Unexpected \(misspelling)")
        }
    }
}
