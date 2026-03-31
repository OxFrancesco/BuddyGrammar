import Foundation

struct RewriteRequest: Sendable {
    let profile: PromptProfile
    let selectedText: String
}

struct RewriteResult: Sendable {
    let originalText: String
    let rewrittenText: String
}

enum RewriteFailure: LocalizedError, Equatable {
    case missingAPIKey
    case accessibilityPermissionDenied
    case selectionUnavailable
    case emptySelection
    case network(String)
    case unexpectedResponse
    case busy
    case pasteFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your OpenRouter API key in Settings."
        case .accessibilityPermissionDenied:
            "BuddyGrammar needs Accessibility permission to read or replace selected text."
        case .selectionUnavailable:
            "Could not read the current selection."
        case .emptySelection:
            "The selected text is empty."
        case .network(let message):
            message
        case .unexpectedResponse:
            "OpenRouter returned an empty or unreadable response."
        case .busy:
            "BuddyGrammar is already processing another prompt."
        case .pasteFailed:
            "BuddyGrammar could not paste the rewritten text back into the active app."
        }
    }
}
