import Foundation

public enum EmojiQualification: String, Codable, Equatable, Sendable {
    case component
    case fullyQualified = "fully-qualified"
    case minimallyQualified = "minimally-qualified"
    case unqualified
}

public struct UnicodeEmojiTestEntry: Equatable, Sendable {
    public let codePoints: [String]
    public let qualification: EmojiQualification
    public let sequence: String
    public let name: String
    public let group: String
    public let subgroup: String
}

public struct UnicodeEmojiTestDocument: Equatable, Sendable {
    public let version: String
    public let date: String?
    public let entries: [UnicodeEmojiTestEntry]

    public var fullyQualifiedEntries: [UnicodeEmojiTestEntry] {
        entries.filter { $0.qualification == .fullyQualified }
    }
}

public enum UnicodeEmojiTestParserError: Error, Equatable, Sendable {
    case missingVersion
    case entryOutsideGroup(line: Int)
    case malformedEntry(line: Int)
}

/// Pure parser for Unicode's `emoji-test.txt` format. It deliberately retains
/// all qualification states so generation can explicitly select only the RGI
/// fully-qualified keyboard sequences.
public enum UnicodeEmojiTestParser {
    public static func parse(_ source: String) throws -> UnicodeEmojiTestDocument {
        var version: String?
        var date: String?
        var group: String?
        var subgroup: String?
        var entries: [UnicodeEmojiTestEntry] = []

        let lines = source.split(omittingEmptySubsequences: false) { $0.isNewline }
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let value = metadataValue(in: line, prefix: "# Version:") {
                version = value
                continue
            }
            if let value = metadataValue(in: line, prefix: "# Date:") {
                date = value
                continue
            }
            if let value = metadataValue(in: line, prefix: "# group:") {
                group = value
                subgroup = nil
                continue
            }
            if let value = metadataValue(in: line, prefix: "# subgroup:") {
                subgroup = value
                continue
            }
            guard !line.hasPrefix("#") else { continue }
            guard let group, let subgroup else {
                throw UnicodeEmojiTestParserError.entryOutsideGroup(line: lineNumber)
            }
            guard let semicolon = line.firstIndex(of: ";"),
                  let hash = line[semicolon...].firstIndex(of: "#") else {
                throw UnicodeEmojiTestParserError.malformedEntry(line: lineNumber)
            }

            let codePoints = line[..<semicolon]
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
            let rawQualification = String(line[line.index(after: semicolon)..<hash])
                .trimmingCharacters(in: .whitespaces)
            guard !codePoints.isEmpty,
                  let qualification = EmojiQualification(rawValue: rawQualification),
                  let sequence = unicodeSequence(from: codePoints) else {
                throw UnicodeEmojiTestParserError.malformedEntry(line: lineNumber)
            }

            let comment = String(line[line.index(after: hash)...])
                .trimmingCharacters(in: .whitespaces)
                .split(whereSeparator: { $0.isWhitespace })
            guard let emojiVersionIndex = comment.firstIndex(where: {
                $0.first == "E" && $0.dropFirst().first?.isNumber == true
            }), emojiVersionIndex > comment.startIndex,
                  comment.index(after: emojiVersionIndex) < comment.endIndex else {
                throw UnicodeEmojiTestParserError.malformedEntry(line: lineNumber)
            }
            let name = comment[comment.index(after: emojiVersionIndex)...]
                .joined(separator: " ")

            entries.append(
                UnicodeEmojiTestEntry(
                    codePoints: codePoints,
                    qualification: qualification,
                    sequence: sequence,
                    name: name,
                    group: group,
                    subgroup: subgroup
                )
            )
        }

        guard let version else { throw UnicodeEmojiTestParserError.missingVersion }
        return UnicodeEmojiTestDocument(version: version, date: date, entries: entries)
    }

    private static func metadataValue(in line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func unicodeSequence(from codePoints: [String]) -> String? {
        var sequence = ""
        for codePoint in codePoints {
            guard let value = UInt32(codePoint, radix: 16),
                  let scalar = UnicodeScalar(value) else { return nil }
            sequence.unicodeScalars.append(scalar)
        }
        return sequence
    }
}

public enum EmojiCatalogError: Error, Equatable, Sendable {
    case missingBundledCatalog
    case unsupportedSchemaVersion(Int)
    case unsupportedUnicodeVersion(String)
    case invalidCatalog
}

public struct EmojiCatalog: Decodable, Equatable, Sendable {
    public static let supportedUnicodeVersion = "17.0"

    public let schemaVersion: Int
    public let unicodeVersion: String
    public let source: String
    public let sourceDate: String
    public let qualification: EmojiQualification
    public let fullyQualifiedSequenceCount: Int
    public let categories: [EmojiCategory]

    public static func bundled() throws -> EmojiCatalog {
        guard let url = Bundle.module.url(
            forResource: "EmojiCatalog",
            withExtension: "json"
        ) else {
            throw EmojiCatalogError.missingBundledCatalog
        }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> EmojiCatalog {
        let catalog = try JSONDecoder().decode(EmojiCatalog.self, from: data)
        guard catalog.schemaVersion == 1 else {
            throw EmojiCatalogError.unsupportedSchemaVersion(catalog.schemaVersion)
        }
        guard catalog.unicodeVersion == supportedUnicodeVersion else {
            throw EmojiCatalogError.unsupportedUnicodeVersion(catalog.unicodeVersion)
        }

        let entries = catalog.allEntries
        let sequences = entries.map(\.sequence)
        guard !catalog.categories.isEmpty,
              catalog.categories.allSatisfy({ !$0.entries.isEmpty }),
              catalog.qualification == .fullyQualified,
              entries.count == catalog.fullyQualifiedSequenceCount,
              Set(sequences).count == sequences.count else {
            throw EmojiCatalogError.invalidCatalog
        }
        return catalog
    }

    public static let empty = EmojiCatalog(
        schemaVersion: 1,
        unicodeVersion: supportedUnicodeVersion,
        source: "",
        sourceDate: "",
        qualification: .fullyQualified,
        fullyQualifiedSequenceCount: 0,
        categories: []
    )

    /// Includes palette entries and every nested skin-tone variant exactly
    /// once, in Unicode's recommended CLDR keyboard order.
    public var allEntries: [EmojiEntry] {
        categories.flatMap { category in
            category.entries.flatMap { entry in
                [entry] + entry.variants.map { EmojiEntry(variant: $0) }
            }
        }
    }

    /// Resolves both a palette base and a nested skin-tone sequence. This is
    /// used to restore recents without storing catalog objects in UserDefaults.
    public func entry(for sequence: String) -> EmojiEntry? {
        for category in categories {
            for entry in category.entries {
                if entry.sequence == sequence { return entry }
                if let variant = entry.variants.first(where: { $0.sequence == sequence }) {
                    return EmojiEntry(variant: variant)
                }
            }
        }
        return nil
    }

    /// English search over names, group/subgroup-derived keywords, and nested
    /// variant names. Results stay in the source file's CLDR palette order.
    public func search(_ query: String, limit: Int = 120) -> [EmojiEntry] {
        let normalizedQuery = Self.normalizedSearchText(query)
        guard limit > 0, !normalizedQuery.isEmpty else { return [] }
        let tokens = normalizedQuery.split(separator: " ").map(String.init)

        let ranked = categories
            .flatMap(\.entries)
            .enumerated()
            .compactMap { index, entry -> (entry: EmojiEntry, rank: Int, index: Int)? in
                let normalizedName = Self.normalizedSearchText(entry.name)
                let normalizedVariantNames = entry.variants.map {
                    Self.normalizedSearchText($0.name)
                }
                let variantTerms = entry.variants.flatMap { [$0.name] + $0.keywords }
                let searchText = Self.normalizedSearchText(
                    ([entry.name] + entry.keywords + variantTerms).joined(separator: " ")
                )
                guard tokens.allSatisfy({ searchText.contains($0) }) else { return nil }

                let rank: Int
                if normalizedName == normalizedQuery {
                    rank = 0
                } else if normalizedName.hasPrefix(normalizedQuery) {
                    rank = 1
                } else if normalizedName.contains(normalizedQuery) {
                    rank = 2
                } else if normalizedVariantNames.contains(where: {
                    $0.contains(normalizedQuery)
                }) {
                    // A tone query should surface the selectable base key,
                    // ahead of unrelated mixed-tone sequences whose own long
                    // Unicode name happens to contain the same phrase.
                    rank = 2
                } else {
                    rank = 3
                }
                return (entry, rank, index)
            }
            .sorted { lhs, rhs in
                lhs.rank == rhs.rank ? lhs.index < rhs.index : lhs.rank < rhs.rank
            }
        return Array(ranked.prefix(limit).map(\.entry))
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public struct EmojiCategory: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let icon: String
    public let entries: [EmojiEntry]
}

public struct EmojiEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { sequence }
    public var qualification: EmojiQualification { .fullyQualified }

    public let sequence: String
    public let name: String
    public let keywords: [String]
    public let variants: [EmojiVariant]

    fileprivate init(variant: EmojiVariant) {
        sequence = variant.sequence
        name = variant.name
        keywords = variant.keywords
        variants = []
    }
}

public struct EmojiVariant: Codable, Equatable, Identifiable, Sendable {
    public var id: String { sequence }
    public var qualification: EmojiQualification { .fullyQualified }

    public let sequence: String
    public let name: String
    public let keywords: [String]
    public let skinTones: [String]
}
