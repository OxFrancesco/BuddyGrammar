import Foundation

public struct ElevenLabsTranscript: Decodable, Equatable, Sendable {
    public let text: String
    public let languageCode: String?
    public let languageProbability: Double?

    private enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
        case languageProbability = "language_probability"
    }
}

public enum TranscriptionError: LocalizedError, Equatable, Sendable {
    case emptyAudio
    case invalidResponse
    case emptyTranscript
    case timedOut
    case server(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .emptyAudio:
            "The recording did not contain any audio."
        case .invalidResponse:
            "ElevenLabs returned an unreadable response."
        case .emptyTranscript:
            "ElevenLabs could not hear any speech in the recording."
        case .timedOut:
            "Transcription took too long. Check your connection and try again."
        case .server(_, let message):
            message
        }
    }
}

public actor ElevenLabsTranscriptionClient {
    private let session: URLSession
    private let endpoint: URL
    private let requestTimeout: Duration

    public init(
        session: URLSession = .shared,
        endpoint: URL = BuddyGrammarConfiguration.apiBaseURL.appending(path: "v1/transcribe"),
        requestTimeout: Duration = .seconds(90)
    ) {
        self.session = session
        self.endpoint = endpoint
        self.requestTimeout = requestTimeout
    }

    public func transcribe(
        audioData: Data,
        clientID: UUID,
        languageCode: String? = nil
    ) async throws -> ElevenLabsTranscript {
        guard !audioData.isEmpty else { throw TranscriptionError.emptyAudio }

        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientID.uuidString, forHTTPHeaderField: "X-BuddyGrammar-Client-ID")
        if let languageCode, !languageCode.isEmpty {
            request.setValue(languageCode, forHTTPHeaderField: "X-Buddy-Language-Code")
        }
        request.httpBody = audioData

        let dataAndResponse: (Data, URLResponse)
        do {
            dataAndResponse = try await withThrowingTaskGroup(
                of: (Data, URLResponse).self
            ) { group in
                group.addTask { [session, request] in
                    try await session.data(for: request)
                }
                group.addTask { [requestTimeout] in
                    try await Task.sleep(for: requestTimeout)
                    throw TranscriptionError.timedOut
                }
                defer { group.cancelAll() }
                guard let firstResult = try await group.next() else {
                    throw TranscriptionError.invalidResponse
                }
                return firstResult
            }
        } catch let error as URLError where error.code == .timedOut {
            throw TranscriptionError.timedOut
        }
        let (data, response) = dataAndResponse
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TranscriptionError.server(
                statusCode: httpResponse.statusCode,
                message: Self.serverMessage(from: data, statusCode: httpResponse.statusCode)
            )
        }

        let transcript = try JSONDecoder().decode(ElevenLabsTranscript.self, from: data)
        let trimmed = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.emptyTranscript }
        return ElevenLabsTranscript(
            text: trimmed,
            languageCode: transcript.languageCode,
            languageProbability: transcript.languageProbability
        )
    }

    private static func serverMessage(from data: Data, statusCode: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // The BuddyGrammar worker reports failures as
            // {error: {code, message}}; other providers use {detail: ...}.
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.isEmpty {
                return message
            }
            if let detail = object["detail"] as? String, !detail.isEmpty {
                return detail
            }
            if let detail = object["detail"] as? [String: Any],
               let message = detail["message"] as? String,
               !message.isEmpty {
                return message
            }
        }
        return HTTPURLResponse.localizedString(forStatusCode: statusCode)
    }
}
