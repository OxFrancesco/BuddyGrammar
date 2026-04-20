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
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case voiceRecordingFailed(String)
    case transcriptionUnavailable(String)
    case network(String)
    case unexpectedResponse
    case invalidOutput
    case localModel(String)
    case busy
    case pasteFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your OpenRouter API key in Settings."
        case .accessibilityPermissionDenied:
            "BuddyWrite needs Accessibility permission to read or replace selected text."
        case .selectionUnavailable:
            "Could not read the current selection."
        case .emptySelection:
            "The selected text is empty."
        case .microphonePermissionDenied:
            "BuddyWrite needs Microphone permission for dictation."
        case .speechRecognitionPermissionDenied:
            "BuddyWrite needs Speech Recognition permission for local transcription."
        case .voiceRecordingFailed(let message):
            message
        case .transcriptionUnavailable(let message):
            message
        case .network(let message):
            message
        case .unexpectedResponse:
            "OpenRouter returned an empty or unreadable response."
        case .invalidOutput:
            "The model returned text BuddyWrite could not safely apply."
        case .localModel(let message):
            message
        case .busy:
            "BuddyWrite is already processing another prompt."
        case .pasteFailed:
            "BuddyWrite could not paste the rewritten text back into the active app."
        }
    }
}
