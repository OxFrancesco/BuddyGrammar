@testable import BuddyGrammar
import XCTest

final class OpenRouterClientTests: XCTestCase {
    func testPayloadIncludesExpectedModelAndInstruction() throws {
        let payload = OpenRouterRequestFactory.makePayload(
            instruction: "Fix grammar only.",
            selectedText: "this are bad"
        )

        XCTAssertEqual(payload.model, "openai/gpt-5.4-nano")
        XCTAssertEqual(payload.messages.first?.content, "Fix grammar only.")
        XCTAssertEqual(payload.messages.last?.content, "this are bad")
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
}
