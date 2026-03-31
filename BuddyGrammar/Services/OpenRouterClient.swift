import Foundation

actor OpenRouterClient {
    private let session: URLSession
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func rewrite(_ request: RewriteRequest, apiKey: String) async throws -> RewriteResult {
        let payload = OpenRouterRequestFactory.makePayload(
            instruction: request.profile.instruction,
            selectedText: request.selectedText
        )

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("BuddyGrammar", forHTTPHeaderField: "X-Title")
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: urlRequest)
        let rewritten = try Self.parseResponse(data: data, response: response)
        return RewriteResult(originalText: request.selectedText, rewrittenText: rewritten)
    }

    static func parseResponse(data: Data, response: URLResponse) throws -> String {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RewriteFailure.unexpectedResponse
        }

        if !(200 ..< 300).contains(httpResponse.statusCode) {
            let errorMessage = (try? JSONDecoder().decode(OpenRouterErrorEnvelope.self, from: data).error.message)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw RewriteFailure.network(errorMessage)
        }

        let decoded = try JSONDecoder().decode(OpenRouterChatResponse.self, from: data)
        if let content = decoded.firstContent?.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return content
        }
        throw RewriteFailure.unexpectedResponse
    }
}

enum OpenRouterRequestFactory {
    static func makePayload(instruction: String, selectedText: String) -> OpenRouterChatRequest {
        OpenRouterChatRequest(
            model: "openai/gpt-5.4-nano",
            temperature: 0.1,
            maxCompletionTokens: max(256, min(2_048, selectedText.count * 2)),
            messages: [
                .init(role: "system", content: instruction),
                .init(role: "user", content: selectedText)
            ]
        )
    }
}

struct OpenRouterChatRequest: Encodable {
    let model: String
    let temperature: Double
    let maxCompletionTokens: Int
    let messages: [OpenRouterMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case messages
        case maxCompletionTokens = "max_completion_tokens"
    }
}

struct OpenRouterMessage: Codable {
    let role: String
    let content: String
}

private struct OpenRouterChatResponse: Decodable {
    let choices: [OpenRouterChoice]

    var firstContent: String? {
        choices.first?.message.content.stringValue
    }
}

private struct OpenRouterChoice: Decodable {
    let message: OpenRouterResponseMessage
}

private struct OpenRouterResponseMessage: Decodable {
    let content: OpenRouterContent
}

private struct OpenRouterErrorEnvelope: Decodable {
    let error: OpenRouterErrorPayload
}

private struct OpenRouterErrorPayload: Decodable {
    let message: String
}

private enum OpenRouterContent: Decodable {
    case string(String)
    case array([OpenRouterContentPart])

    var stringValue: String? {
        switch self {
        case .string(let string):
            string
        case .array(let parts):
            parts.compactMap(\.text).joined(separator: "\n")
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            self = .array(try container.decode([OpenRouterContentPart].self))
        }
    }
}

private struct OpenRouterContentPart: Decodable {
    let text: String?
}
