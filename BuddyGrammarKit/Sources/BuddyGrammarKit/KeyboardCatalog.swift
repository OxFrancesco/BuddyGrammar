import Foundation

public enum KeyboardCatalogError: Error, Equatable, Sendable {
    case missingBundledCatalog
    case unsupportedSchemaVersion(Int)
    case invalidCatalog
}

public enum KeyboardCatalogFieldKind: String, CaseIterable, Sendable {
    case text
    case multiline
    case literal
    case name
    case search
    case email
    case url
    case number
    case decimal
    case phone
    case datetime
    case code
    case oneTimeCode
    case password
}

public struct KeyboardCatalog: Decodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let catalogRevision: String
    public let defaultLanguageId: String
    public let fallbackLayoutProfileId: String
    public let layouts: [Layout]
    public let layoutProfiles: [LayoutProfile]
    public let languages: [Language]
    public let gestures: Gestures

    public static func bundled() throws -> KeyboardCatalog {
        guard let url = Bundle.module.url(
            forResource: "KeyboardCatalog",
            withExtension: "json"
        ) else {
            throw KeyboardCatalogError.missingBundledCatalog
        }
        let catalog = try JSONDecoder().decode(
            KeyboardCatalog.self,
            from: Data(contentsOf: url)
        )
        guard catalog.schemaVersion == 1 else {
            throw KeyboardCatalogError.unsupportedSchemaVersion(catalog.schemaVersion)
        }
        guard catalog.languages.contains(where: { $0.id == catalog.defaultLanguageId }),
              catalog.layoutProfiles.contains(where: {
                  $0.id == catalog.fallbackLayoutProfileId
              }) else {
            throw KeyboardCatalogError.invalidCatalog
        }
        return catalog
    }

    public func language(for localeIdentifier: String?) -> Language {
        let normalized = Self.normalizedLocale(localeIdentifier)
        let base = normalized.split(separator: "-").first.map(String.init).orEmpty
        let language = languages.first { language in
            language.localeAliases.contains { alias in
                let candidate = Self.normalizedLocale(alias)
                return candidate == normalized || (!base.isEmpty && candidate == base)
            }
        }
        return language
            ?? languages.first(where: { $0.id == defaultLanguageId })
            ?? Language.fallback
    }

    /// Cycles only languages actually shipped in this catalog. This remains
    /// independent of the system input-mode switch managed by iOS.
    public func nextLanguage(after localeIdentifier: String?) -> Language {
        guard !languages.isEmpty else { return .fallback }
        let current = language(for: localeIdentifier)
        guard let index = languages.firstIndex(where: { $0.id == current.id }) else {
            return languages[0]
        }
        return languages[(index + 1) % languages.count]
    }

    public func languageSwitchAccessibilityLabel(
        from current: Language,
        to next: Language,
        displayLocaleIdentifier: String? = "en"
    ) -> String {
        let displayLanguage = LanguageSupport.primaryCode(
            for: displayLocaleIdentifier
        )
        let currentName = current.displayNames[displayLanguage]
            ?? current.displayNames["en"]
            ?? current.id.uppercased()
        let nextName = next.displayNames[displayLanguage]
            ?? next.displayNames["en"]
            ?? next.id.uppercased()
        return "Keyboard language " + currentName + ". Switch to " + nextName
    }

    public func layoutProfile(for language: Language) -> LayoutProfile {
        layoutProfiles.first(where: { $0.id == language.defaultLayoutProfileId })
            ?? layoutProfiles.first(where: { $0.id == fallbackLayoutProfileId })
            ?? .fallback
    }

    public func presentation(
        for fieldKind: KeyboardCatalogFieldKind,
        localeIdentifier: String?
    ) -> Presentation {
        let language = language(for: localeIdentifier)
        let profile = layoutProfile(for: language)
        let layout = layouts.first(where: { $0.id == profile.layoutId })
            ?? layouts.first
            ?? .fallback
        let variant = layout.fieldVariants.first(where: {
            $0.fieldKinds.contains(fieldKind.rawValue)
        }) ?? layout.fieldVariants.first(where: { $0.id == "text" }) ?? .fallback
        let inlineKeys = variant.inlineKeys.map { key in
            guard variant.usesLocaleDecimalSeparator == true,
                  key.id == "decimal-separator" else { return key }
            return InlineKey(
                id: key.id,
                label: language.punctuation.decimalSeparator,
                output: language.punctuation.decimalSeparator
            )
        }
        return Presentation(
            fieldKind: fieldKind,
            language: language,
            profile: profile,
            layout: layout,
            primaryPlane: variant.primaryPlane,
            autoCapitalization: variant.autoCapitalization,
            suggestionMode: variant.suggestionMode,
            inlineKeys: inlineKeys,
            returnIntent: variant.returnIntent
        )
    }

    private static func normalizedLocale(_ identifier: String?) -> String {
        identifier?
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    public struct Layout: Decodable, Equatable, Sendable {
        public let id: String
        public let letterRows: [[String]]
        public let numberRows: [[String]]
        public let symbolRows: [[String]]
        public let fieldVariants: [FieldVariant]

        fileprivate static let fallback = Layout(
            id: "latin-qwerty",
            letterRows: [Array("qwertyuiop").map(String.init), Array("asdfghjkl").map(String.init), Array("zxcvbnm").map(String.init)],
            numberRows: [Array("1234567890").map(String.init)],
            symbolRows: [],
            fieldVariants: [.fallback]
        )
    }

    public struct FieldVariant: Decodable, Equatable, Sendable {
        public let id: String
        public let fieldKinds: [String]
        public let primaryPlane: String
        public let autoCapitalization: String
        public let suggestionMode: String
        public let inlineKeys: [InlineKey]
        public let returnIntent: String
        public let usesLocaleDecimalSeparator: Bool?

        fileprivate static let fallback = FieldVariant(
            id: "text",
            fieldKinds: ["text"],
            primaryPlane: "letters",
            autoCapitalization: "sentences",
            suggestionMode: "full",
            inlineKeys: [],
            returnIntent: "newline",
            usesLocaleDecimalSeparator: nil
        )
    }

    public struct InlineKey: Decodable, Equatable, Sendable {
        public let id: String
        public let label: String
        public let output: String

        public init(id: String, label: String, output: String) {
            self.id = id
            self.label = label
            self.output = output
        }
    }

    public struct LayoutProfile: Decodable, Equatable, Sendable {
        public let id: String
        public let layoutId: String
        public let languageId: String
        public let spaceLabel: String
        public let returnLabels: [String: String]

        fileprivate static let fallback = LayoutProfile(
            id: "en-qwerty",
            layoutId: "latin-qwerty",
            languageId: "en",
            spaceLabel: "space",
            returnLabels: [:]
        )
    }

    public struct Language: Decodable, Equatable, Sendable {
        public let id: String
        public let localeAliases: [String]
        public let defaultLayoutProfileId: String
        public let displayNames: [String: String]
        public let punctuation: Punctuation
        public let alternates: [String: [String]]

        fileprivate static let fallback = Language(
            id: "en",
            localeAliases: ["en"],
            defaultLayoutProfileId: "en-qwerty",
            displayNames: ["en": "English"],
            punctuation: Punctuation(
                decimalSeparator: ".",
                thousandsSeparator: ",",
                sentenceTerminators: [".", "!", "?"]
            ),
            alternates: [:]
        )
    }

    public struct Punctuation: Decodable, Equatable, Sendable {
        public let decimalSeparator: String
        public let thousandsSeparator: String
        public let sentenceTerminators: [String]
    }

    public struct Gestures: Decodable, Equatable, Sendable {
        public let swipe: Swipe
        public let spaceCursor: SpaceCursor
        public let deleteRepeat: DeleteRepeat
    }

    public struct Swipe: Decodable, Equatable, Sendable {
        public let minimumPointCount: Int
        public let repeatedLetterStrategy: String
        public let minimumDwellMilliseconds: Int
        public let minimumDwellSamples: Int
        public let maximumDwellDriftKeyUnits: Double
    }

    public struct SpaceCursor: Decodable, Equatable, Sendable {
        public let activationMilliseconds: Int
        public let pointsPerGrapheme: Int
    }

    public struct DeleteRepeat: Decodable, Equatable, Sendable {
        public let initialDelayMilliseconds: Int
        public let intervalMilliseconds: Int
    }

    public struct Presentation: Equatable, Sendable {
        public let fieldKind: KeyboardCatalogFieldKind
        public let language: Language
        public let profile: LayoutProfile
        public let layout: Layout
        public let primaryPlane: String
        public let autoCapitalization: String
        public let suggestionMode: String
        public let inlineKeys: [InlineKey]
        public let returnIntent: String

        public func returnLabel(overridingIntent: String? = nil) -> String {
            let intent = overridingIntent ?? returnIntent
            return profile.returnLabels[intent]
                ?? profile.returnLabels[returnIntent]
                ?? intent
        }

        public var numericKeyRows: [[String]] {
            let digits = layout.numberRows
                .flatMap { $0 }
                .filter { value in
                    !value.isEmpty && value.allSatisfy(\.isNumber)
                }
            guard digits.count >= 10 else { return layout.numberRows }
            return [
                Array(digits[0..<3]),
                Array(digits[3..<6]),
                Array(digits[6..<9]),
                [digits[9]],
            ]
        }

        public var contextualInlineKeys: [InlineKey] {
            guard fieldKind == .datetime else { return inlineKeys }
            let candidates = layout.numberRows.flatMap { $0 }
            return ["/", "-", ":"].compactMap { output in
                guard candidates.contains(output) else { return nil }
                return InlineKey(
                    id: "datetime-\(output)",
                    label: output,
                    output: output
                )
            }
        }

        public var usesNumericFieldLayout: Bool {
            primaryPlane == "numbers"
                && [.number, .decimal, .phone, .datetime].contains(fieldKind)
        }

        public func resolvedAutoCapitalization(
            hostMode: EditorAutoCapitalizationMode
        ) -> EditorAutoCapitalizationMode {
            autoCapitalization == "never" ? .none : hostMode
        }
    }
}

public extension EditorFieldKind {
    var catalogFieldKind: KeyboardCatalogFieldKind {
        switch self {
        case .plainText, .unknown:
            .text
        case .multiline:
            .multiline
        case .literal:
            .literal
        case .search:
            .search
        case .emailAddress:
            .email
        case .url:
            .url
        case .personName:
            .name
        case .phoneNumber:
            .phone
        case .number:
            .number
        case .decimal:
            .decimal
        case .dateTime:
            .datetime
        case .oneTimeCode:
            .oneTimeCode
        case .password:
            .password
        case .code:
            .code
        }
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
