import Foundation

public enum CloudCorrectionError: LocalizedError, Equatable, Sendable {
    case emptyInput
    case rejectedOutput
    case invalidResponse
    case timedOut
    case server(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            "There is no text to correct."
        case .rejectedOutput:
            "The correction service returned text that could not be applied safely."
        case .invalidResponse:
            "The correction service returned an unreadable response."
        case .timedOut:
            "Polishing took too long, so the original transcript was kept."
        case .server(_, let message):
            message
        }
    }
}

public actor OpenRouterCorrectionClient {
    private let session: URLSession
    private let endpoint: URL
    private let requestTimeout: Duration

    public init(
        session: URLSession = .shared,
        endpoint: URL = BuddyGrammarConfiguration.apiBaseURL.appending(path: "v1/correct"),
        requestTimeout: Duration = .seconds(8)
    ) {
        self.session = session
        self.endpoint = endpoint
        self.requestTimeout = requestTimeout
    }

    /// Opens the TLS connection to the API ahead of time so the first
    /// correction does not pay DNS + TLS setup on top of model latency.
    public func warmUpConnection() async {
        var request = URLRequest(
            url: BuddyGrammarConfiguration.apiBaseURL.appending(path: "health"),
            timeoutInterval: 10
        )
        request.httpMethod = "GET"
        _ = try? await session.data(for: request)
    }

    public func correct(
        text: String,
        clientID: UUID,
        modelID: String,
        instruction: String
    ) async throws -> String {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw CloudCorrectionError.emptyInput }

        let payload = CorrectionRequest(
            text: input,
            modelID: modelID,
            instruction: instruction
        )

        var request = URLRequest(url: endpoint, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientID.uuidString, forHTTPHeaderField: "X-BuddyGrammar-Client-ID")
        request.httpBody = try JSONEncoder().encode(payload)

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
                    throw CloudCorrectionError.timedOut
                }
                defer { group.cancelAll() }
                guard let firstResult = try await group.next() else {
                    throw CloudCorrectionError.invalidResponse
                }
                return firstResult
            }
        } catch let error as URLError where error.code == .timedOut {
            throw CloudCorrectionError.timedOut
        }
        let (data, response) = dataAndResponse
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudCorrectionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CloudCorrectionError.server(
                statusCode: httpResponse.statusCode,
                message: Self.serverMessage(from: data, statusCode: httpResponse.statusCode)
            )
        }

        let envelope = try JSONDecoder().decode(CorrectionResponse.self, from: data)
        return try CorrectionOutputGuard.sanitize(envelope.text, relativeTo: input)
    }

    private static func serverMessage(from data: Data, statusCode: Int) -> String {
        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
           !envelope.error.message.isEmpty {
            return envelope.error.message
        }
        return HTTPURLResponse.localizedString(forStatusCode: statusCode)
    }
}

public enum CorrectionOutputGuard {
    private static let disallowedPrefixes = [
        "here is the corrected text",
        "here's the corrected text",
        "corrected text:",
        "the corrected text is",
        "grammar correction:",
        "fixed text:",
        "corrected version:",
        "here is the revised text",
        "here's the revised text",
    ]

    public static func sanitize(_ output: String, relativeTo input: String) throws -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CloudCorrectionError.rejectedOutput }

        let normalized = trimmed
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
        guard !disallowedPrefixes.contains(where: normalized.hasPrefix) else {
            throw CloudCorrectionError.rejectedOutput
        }

        let maximumCharacters = max(500, input.count * 4)
        guard trimmed.count <= maximumCharacters else {
            throw CloudCorrectionError.rejectedOutput
        }
        return trimmed
    }
}

private struct CorrectionRequest: Encodable {
    let text: String
    let modelID: String
    let instruction: String
}

private struct CorrectionResponse: Decodable {
    let text: String
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorPayload
}

private struct APIErrorPayload: Decodable {
    let message: String
}
