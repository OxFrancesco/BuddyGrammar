import Foundation

public enum BuddyGrammarConfiguration {
    public static let appGroupIdentifier = "group.com.francescooddo.BuddyGrammar"

    public static let defaultOpenRouterModelID = "openai/gpt-5.4-nano"
    public static let defaultElevenLabsModelID = "scribe_v2"
    public static let pendingTranscriptLifetime: TimeInterval = 24 * 60 * 60

    public static var apiBaseURL: URL {
        guard let url = URL(string: "https://buddygrammar-api.oddofrancesco000.workers.dev") else {
            fatalError("BuddyGrammar API URL is invalid.")
        }
        return url
    }

    public static let standardCorrectionInstruction = """
    Fix grammar, spelling, punctuation, and capitalization only.
    Preserve the original language, wording, tone, and meaning as much as possible.
    Do not add explanations, quotes, prefixes, or suffixes.
    Return only the corrected text.
    """
}
