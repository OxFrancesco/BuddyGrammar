import BuddyGrammarKit
import Foundation
import Testing

@Suite("Unicode emoji catalog")
struct EmojiCatalogTests {
    @Test("emoji-test parser preserves groups, English names, and qualification")
    func parsesOfficialFormat() throws {
        let source = """
        # emoji-test.txt
        # Date: 2025-08-04, 20:55:31 GMT
        # Version: 17.0
        # group: Smileys & Emotion
        # subgroup: face-smiling
        1F600                                                  ; fully-qualified     # 😀 E1.0 grinning face
        263A FE0F                                              ; fully-qualified     # ☺️ E0.6 smiling face
        263A                                                   ; unqualified         # ☺ E0.6 smiling face
        # group: People & Body
        # subgroup: hand-fingers-closed
        1F44D                                                  ; fully-qualified     # 👍 E0.6 thumbs up
        1F44D 1F3FD                                            ; fully-qualified     # 👍🏽 E1.0 thumbs up: medium skin tone
        """

        let document = try UnicodeEmojiTestParser.parse(source)

        #expect(document.version == "17.0")
        #expect(document.date == "2025-08-04, 20:55:31 GMT")
        #expect(document.entries.count == 5)
        #expect(document.entries[0].group == "Smileys & Emotion")
        #expect(document.entries[0].subgroup == "face-smiling")
        #expect(document.entries[0].name == "grinning face")
        #expect(document.entries[0].qualification == .fullyQualified)
        #expect(document.entries[2].qualification == .unqualified)
        #expect(document.fullyQualifiedEntries.map(\.sequence) == ["😀", "☺️", "👍", "👍🏽"])
    }

    @Test("bundled catalog is the deterministic fully-qualified Emoji 17 set")
    func bundledCatalogMetadataAndIntegrity() throws {
        let catalog = try EmojiCatalog.bundled()
        let sequences = catalog.allEntries.map(\.sequence)

        #expect(catalog.schemaVersion == 1)
        #expect(catalog.unicodeVersion == "17.0")
        #expect(catalog.source == "https://www.unicode.org/Public/UCD/latest/emoji/emoji-test.txt")
        #expect(catalog.categories.map(\.name).contains("Smileys & Emotion"))
        #expect(catalog.categories.map(\.name).contains("Flags"))
        #expect(catalog.fullyQualifiedSequenceCount == sequences.count)
        #expect(Set(sequences).count == sequences.count)
        #expect(catalog.allEntries.allSatisfy { $0.qualification == .fullyQualified })
    }

    @Test("skin tone sequences are selectable variants of their RGI base")
    func skinToneVariants() throws {
        let catalog = try EmojiCatalog.bundled()
        let thumbsUp = try #require(catalog.entry(for: "👍"))
        let mediumTone = try #require(catalog.entry(for: "👍🏽"))

        #expect(thumbsUp.variants.count == 5)
        #expect(thumbsUp.variants.map(\.sequence).contains("👍🏽"))
        #expect(mediumTone.sequence == "👍🏽")
        #expect(mediumTone.name.contains("medium skin tone"))
        #expect(mediumTone.variants.isEmpty)
    }

    @Test("English names and generated file keywords drive compact search")
    func searchableNamesAndKeywords() throws {
        let catalog = try EmojiCatalog.bundled()

        #expect(catalog.search("grinning", limit: 10).first?.sequence == "😀")
        #expect(catalog.search("face smiling", limit: 20).contains { $0.sequence == "☺️" })
        #expect(catalog.search("medium skin tone", limit: 100).contains { $0.sequence == "👍" })
        #expect(catalog.search("not-an-emoji-name", limit: 10).isEmpty)
        #expect(catalog.search("face", limit: 0).isEmpty)
    }
}
