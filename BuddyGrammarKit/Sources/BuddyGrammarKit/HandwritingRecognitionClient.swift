import Foundation

public enum HandwritingRecognitionError: LocalizedError, Equatable, Sendable {
    case emptyImage
    case invalidResponse
    case emptyRecognition
    case server(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .emptyImage:
            "There is no handwriting to recognize."
        case .invalidResponse:
            "The handwriting service returned an unreadable response."
        case .emptyRecognition:
            "BuddyGrammar could not read that handwriting."
        case .server(_, let message):
            message
        }
    }
}

public actor HandwritingRecognitionClient {
    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = BuddyGrammarConfiguration.apiBaseURL.appending(path: "v1/handwriting")
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func recognize(
        imageData: Data,
        clientID: UUID,
        modelID: String,
        languageCode: String? = nil
    ) async throws -> String {
        guard !imageData.isEmpty else { throw HandwritingRecognitionError.emptyImage }

        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientID.uuidString, forHTTPHeaderField: "X-BuddyGrammar-Client-ID")
        request.setValue(modelID, forHTTPHeaderField: "X-Buddy-Model-ID")
        if let languageCode, !languageCode.isEmpty {
            request.setValue(languageCode, forHTTPHeaderField: "X-Buddy-Language-Code")
        }
        request.httpBody = imageData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HandwritingRecognitionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HandwritingRecognitionError.server(
                statusCode: httpResponse.statusCode,
                message: Self.serverMessage(from: data, statusCode: httpResponse.statusCode)
            )
        }

        guard let envelope = try? JSONDecoder().decode(RecognitionResponse.self, from: data) else {
            throw HandwritingRecognitionError.invalidResponse
        }
        let text = envelope.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw HandwritingRecognitionError.emptyRecognition }
        return text
    }

    private static func serverMessage(from data: Data, statusCode: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        return HTTPURLResponse.localizedString(forStatusCode: statusCode)
    }
}

private struct RecognitionResponse: Decodable {
    let text: String
}
