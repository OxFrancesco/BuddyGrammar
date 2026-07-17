import XCTest
@testable import BuddyGrammarKit

final class CloudClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testOpenRouterEncodesRequestAndParsesResponse() async throws {
        let session = makeSession()
        let endpoint = URL(string: "https://example.test/correct")!
        let clientID = UUID(uuidString: "83001D6E-7DAA-4BB5-AC9A-07F70129AD11")!
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url, endpoint)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "xi-api-key"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-BuddyGrammar-Client-ID"), clientID.uuidString)
            let body = try requestBody(from: request)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(object["text"] as? String, "this are correct")
            XCTAssertEqual(object["modelID"] as? String, "test/model")
            XCTAssertEqual(object["instruction"] as? String, "Correct it.")

            let response = HTTPURLResponse(
                url: endpoint,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(#"{"text":"This is correct."}"#.utf8)
            return (response, data)
        }

        let client = OpenRouterCorrectionClient(session: session, endpoint: endpoint)
        let result = try await client.correct(
            text: "this are correct",
            clientID: clientID,
            modelID: "test/model",
            instruction: "Correct it."
        )

        XCTAssertEqual(result, "This is correct.")
    }

    func testCorrectionClientStopsAtConfiguredDeadline() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let endpoint = URL(string: "https://example.test/correct")!
        let client = OpenRouterCorrectionClient(
            session: session,
            endpoint: endpoint,
            requestTimeout: .milliseconds(50)
        )

        do {
            _ = try await client.correct(
                text: "this needs correction",
                clientID: UUID(uuidString: "83001D6E-7DAA-4BB5-AC9A-07F70129AD11")!,
                modelID: "test/model",
                instruction: "Correct it."
            )
            XCTFail("Expected correction to time out")
        } catch let error as CloudCorrectionError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func testTranscriptionClientSendsRawAudioAndParsesTranscript() async throws {
        let session = makeSession()
        let endpoint = URL(string: "https://example.test/transcribe")!
        let clientID = UUID(uuidString: "83001D6E-7DAA-4BB5-AC9A-07F70129AD11")!
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url, endpoint)
            XCTAssertNil(request.value(forHTTPHeaderField: "xi-api-key"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/mp4")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-BuddyGrammar-Client-ID"), clientID.uuidString)
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Buddy-Audio-Filename"))
            XCTAssertEqual(try requestBody(from: request), Data([0x01, 0x02, 0x03]))

            let response = HTTPURLResponse(
                url: endpoint,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(
                #"{"text":"Hello from speech.","language_code":"en","language_probability":0.99}"#.utf8
            )
            return (response, data)
        }

        let client = ElevenLabsTranscriptionClient(session: session, endpoint: endpoint)
        let result = try await client.transcribe(
            audioData: Data([0x01, 0x02, 0x03]),
            clientID: clientID
        )

        XCTAssertEqual(result.text, "Hello from speech.")
        XCTAssertEqual(result.languageCode, "en")
    }

    func testTranscriptionClientStopsAtConfiguredDeadline() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let endpoint = URL(string: "https://example.test/transcribe")!
        let client = ElevenLabsTranscriptionClient(
            session: session,
            endpoint: endpoint,
            requestTimeout: .milliseconds(50)
        )

        do {
            _ = try await client.transcribe(
                audioData: Data([0x01, 0x02, 0x03]),
                clientID: UUID(uuidString: "83001D6E-7DAA-4BB5-AC9A-07F70129AD11")!
            )
            XCTFail("Expected transcription to time out")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func testHandwritingClientSendsPNGToSameConfiguredModel() async throws {
        let session = makeSession()
        let endpoint = URL(string: "https://example.test/handwriting")!
        let clientID = UUID(uuidString: "83001D6E-7DAA-4BB5-AC9A-07F70129AD11")!
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url, endpoint)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-BuddyGrammar-Client-ID"), clientID.uuidString)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Buddy-Model-ID"), "test/model")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Buddy-Language-Code"), "en")
            XCTAssertEqual(try requestBody(from: request), imageData)

            let response = HTTPURLResponse(
                url: endpoint,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"text":"Hello world"}"#.utf8))
        }

        let client = HandwritingRecognitionClient(session: session, endpoint: endpoint)
        let result = try await client.recognize(
            imageData: imageData,
            clientID: clientID,
            modelID: "test/model",
            languageCode: "en"
        )

        XCTAssertEqual(result, "Hello world")
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private func requestBody(from request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }

    let stream = try XCTUnwrap(request.httpBodyStream)
    stream.open()
    defer { stream.close() }

    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)

    while true {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeContentData)
        }
        if count == 0 {
            break
        }
        body.append(contentsOf: buffer.prefix(count))
    }

    return body
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class HangingURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
