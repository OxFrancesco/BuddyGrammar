import Foundation

public struct BuddyGrammarSettings: Codable, Equatable, Sendable {
    public var openRouterModelID: String
    public var correctionInstruction: String
    public var autoCorrectDictation: Bool
    public var hasAcceptedCloudProcessing: Bool
    public var hasCompletedOnboarding: Bool

    public init(
        openRouterModelID: String = BuddyGrammarConfiguration.defaultOpenRouterModelID,
        correctionInstruction: String = BuddyGrammarConfiguration.standardCorrectionInstruction,
        autoCorrectDictation: Bool = true,
        hasAcceptedCloudProcessing: Bool = false,
        hasCompletedOnboarding: Bool = false
    ) {
        self.openRouterModelID = openRouterModelID
        self.correctionInstruction = correctionInstruction
        self.autoCorrectDictation = autoCorrectDictation
        self.hasAcceptedCloudProcessing = hasAcceptedCloudProcessing
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public static let `default` = BuddyGrammarSettings()
}

public struct PendingTranscript: Codable, Equatable, Sendable {
    public let text: String
    public let createdAt: Date

    public init(text: String, createdAt: Date = .now) {
        self.text = text
        self.createdAt = createdAt
    }
}
