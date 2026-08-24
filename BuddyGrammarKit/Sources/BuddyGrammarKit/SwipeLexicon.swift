import Foundation

public enum SwipeLexiconError: Error, Equatable, Sendable {
    case invalidEntry(line: Int, value: String)
    case duplicateEntry(line: Int, value: String)
}

/// Parses ranked, original-product swipe lexicons shared by the native
/// keyboards. Line order is rank; blank lines and `#` comments are metadata.
public enum SwipeLexicon {
    public static func parse(source: String) throws -> [String] {
        var words: [String] = []
        var seen = Set<String>()

        for (offset, rawLine) in source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated() {
            let lineNumber = offset + 1
            let word = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, !word.hasPrefix("#") else { continue }
            guard word == word.lowercased(with: Locale(identifier: "it_IT")),
                  let form = SwipeWordNormalizer.normalize(word) else {
                throw SwipeLexiconError.invalidEntry(line: lineNumber, value: word)
            }
            guard seen.insert(form.display).inserted else {
                throw SwipeLexiconError.duplicateEntry(line: lineNumber, value: form.display)
            }
            words.append(form.display)
        }
        return words
    }
}
