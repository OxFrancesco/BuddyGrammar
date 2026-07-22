import BuddyGrammarKit
import Testing

@Suite("Shared keyboard catalog")
struct KeyboardCatalogTests {
    @Test("bundled catalog resolves aliases and safe fallback")
    func localeResolution() throws {
        let catalog = try KeyboardCatalog.bundled()

        #expect(catalog.catalogRevision == "2026.07.1")
        #expect(catalog.language(for: "it_CH").id == "it")
        #expect(catalog.language(for: "IT-it").id == "it")
        #expect(catalog.language(for: "fr-FR").id == "en")
    }

    @Test("language switching cycles the shipped EN and IT packs")
    func languageSwitching() throws {
        let catalog = try KeyboardCatalog.bundled()

        #expect(catalog.nextLanguage(after: "en-US").id == "it")
        #expect(catalog.nextLanguage(after: "it-CH").id == "en")

        let english = catalog.language(for: "en-US")
        let italian = catalog.nextLanguage(after: "en-US")
        #expect(
            catalog.languageSwitchAccessibilityLabel(from: english, to: italian)
                == "Keyboard language English. Switch to Italian"
        )
    }

    @Test("Italian punctuation and alternates come from the catalog")
    func italianLanguagePack() throws {
        let catalog = try KeyboardCatalog.bundled()
        let italian = catalog.language(for: "it-IT")

        #expect(italian.punctuation.decimalSeparator == ",")
        #expect(italian.alternates["e"]?.first == "è")
        #expect(catalog.layoutProfile(for: italian).spaceLabel == "spazio")
    }

    @Test("field presentations expose editor-specific inline keys")
    func fieldPresentations() throws {
        let catalog = try KeyboardCatalog.bundled()

        #expect(
            catalog.presentation(for: .email, localeIdentifier: "en-US")
                .inlineKeys.map(\.output) == ["@", "."]
        )
        #expect(
            catalog.presentation(for: .url, localeIdentifier: "en-US")
                .inlineKeys.map(\.output) == ["/", ".", ".com"]
        )
        #expect(
            catalog.presentation(for: .decimal, localeIdentifier: "it-IT")
                .inlineKeys.map(\.output) == [","]
        )
        #expect(
            catalog.presentation(for: .phone, localeIdentifier: "it-IT")
                .inlineKeys.map(\.output) == ["+", "#", "*"]
        )
    }

    @Test("field plans expose locale labels, numeric rows, and date-time punctuation")
    func dailyKeyboardFieldPlans() throws {
        let catalog = try KeyboardCatalog.bundled()
        let italianSearch = catalog.presentation(
            for: .search,
            localeIdentifier: "it-IT"
        )
        let italianDecimal = catalog.presentation(
            for: .decimal,
            localeIdentifier: "it-IT"
        )
        let dateTime = catalog.presentation(
            for: .datetime,
            localeIdentifier: "en-US"
        )

        #expect(italianSearch.returnLabel() == "cerca")
        #expect(italianSearch.returnLabel(overridingIntent: "send") == "invia")
        #expect(italianSearch.profile.spaceLabel == "spazio")
        #expect(italianDecimal.numericKeyRows == [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["0"],
        ])
        #expect(italianDecimal.contextualInlineKeys.map(\.output) == [","])
        #expect(dateTime.contextualInlineKeys.map(\.output) == ["/", "-", ":"])
    }

    @Test("editor capability field kinds map to catalog surfaces")
    func editorFieldMapping() {
        #expect(EditorFieldKind.plainText.catalogFieldKind == .text)
        #expect(EditorFieldKind.multiline.catalogFieldKind == .multiline)
        #expect(EditorFieldKind.literal.catalogFieldKind == .literal)
        #expect(EditorFieldKind.search.catalogFieldKind == .search)
        #expect(EditorFieldKind.emailAddress.catalogFieldKind == .email)
        #expect(EditorFieldKind.url.catalogFieldKind == .url)
        #expect(EditorFieldKind.phoneNumber.catalogFieldKind == .phone)
        #expect(EditorFieldKind.dateTime.catalogFieldKind == .datetime)
        #expect(EditorFieldKind.code.catalogFieldKind == .code)
        #expect(EditorFieldKind.password.catalogFieldKind == .password)
    }

    @Test("no-suggestions fields have a literal surface distinct from code")
    func literalPresentation() throws {
        let catalog = try KeyboardCatalog.bundled()
        let literal = catalog.presentation(for: .literal, localeIdentifier: "en-US")
        let code = catalog.presentation(for: .code, localeIdentifier: "en-US")

        #expect(literal.suggestionMode == "off")
        #expect(literal.inlineKeys.isEmpty)
        #expect(code.inlineKeys.map(\.output) == ["_", "/", "-"])
        #expect(literal != code)
    }

    @Test("catalog never policy wins while text fields respect host capitalization")
    func capitalizationPolicy() throws {
        let catalog = try KeyboardCatalog.bundled()
        let email = catalog.presentation(for: .email, localeIdentifier: "en-US")
        let text = catalog.presentation(for: .text, localeIdentifier: "en-US")

        #expect(email.resolvedAutoCapitalization(hostMode: .sentences) == .none)
        #expect(text.resolvedAutoCapitalization(hostMode: .words) == .words)
        #expect(text.resolvedAutoCapitalization(hostMode: .none) == .none)
    }
}
