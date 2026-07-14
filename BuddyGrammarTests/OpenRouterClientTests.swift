@testable import BuddyGrammar
import XCTest

final class OpenRouterClientTests: XCTestCase {
    func testPayloadIncludesExpectedModelAndInstruction() throws {
        let payload = OpenRouterRequestFactory.makePayload(
            modelID: OpenRouterModel.defaultID,
            instruction: "Fix grammar only.",
            selectedText: "this are bad"
        )

        XCTAssertEqual(payload.model, OpenRouterModel.defaultID)
        XCTAssertEqual(payload.temperature, 0)
        XCTAssertEqual(payload.messages.first?.content, "Fix grammar only.")
        XCTAssertEqual(payload.messages.last?.content, "this are bad")

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        XCTAssertNil(encoded?["max_completion_tokens"])
    }

    func testParsesTextResponse() throws {
        let data = Data(
            """
            {
              "choices": [
                { "message": { "content": "This is better." } }
              ]
            }
            """.utf8
        )

        let response = HTTPURLResponse(url: URL(string: "https://openrouter.ai")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertEqual(try OpenRouterClient.parseResponse(data: data, response: response), "This is better.")
    }

    func testThrowsReadableErrorOnFailureResponse() {
        let data = Data(
            """
            {
              "error": { "message": "Payment required." }
            }
            """.utf8
        )
        let response = HTTPURLResponse(url: URL(string: "https://openrouter.ai")!, statusCode: 402, httpVersion: nil, headerFields: nil)!

        XCTAssertThrowsError(try OpenRouterClient.parseResponse(data: data, response: response)) { error in
            XCTAssertEqual(error as? RewriteFailure, .network("Payment required."))
        }
    }

    func testParsesModelsResponse() throws {
        let data = Data(
            """
            {
              "data": [
                {
                  "id": "anthropic/claude-sonnet-4",
                  "name": "Claude Sonnet 4",
                  "context_length": 200000
                }
              ]
            }
            """.utf8
        )
        let response = HTTPURLResponse(
            url: URL(string: "https://openrouter.ai/api/v1/models")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let models = try OpenRouterClient.parseModelsResponse(data: data, response: response)
        XCTAssertEqual(models, [
            OpenRouterModelSummary(
                id: "anthropic/claude-sonnet-4",
                name: "Claude Sonnet 4",
                contextLength: 200000
            )
        ])
    }
}
