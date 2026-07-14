import Foundation

public struct KeyboardDictationSession: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Equatable, Sendable {
        case launching
        case recording
        case stopRequested
        case transcribing
        case ready
        case failed
    }

    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let phase: Phase
    public let transcript: String?
    public let languageCode: String?
    public let errorMessage: String?

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        phase: Phase,
        transcript: String? = nil,
        languageCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.phase = phase
        self.transcript = transcript
        self.languageCode = languageCode
        self.errorMessage = errorMessage
    }

    public func updating(
        phase: Phase,
        transcript: String? = nil,
        languageCode: String? = nil,
        errorMessage: String? = nil,
        at date: Date
    ) -> KeyboardDictationSession {
        KeyboardDictationSession(
            id: id,
            createdAt: createdAt,
            updatedAt: date,
            phase: phase,
            transcript: transcript,
            languageCode: languageCode ?? self.languageCode,
            errorMessage: errorMessage
        )
    }
}
