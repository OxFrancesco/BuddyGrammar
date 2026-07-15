@testable import BuddyGrammar
import XCTest

@MainActor
final class MockSpeechEngine: SpeechTranscriptionEngine {
    var available: Bool
    var transcript: String
    var requiresAuthorization = true
    var transcriptionError: Error?
    var streamingSession: (any StreamingSpeechTranscriptionSession)?
    var transcribeCallCount = 0

    init(available: Bool, transcript: String) {
        self.available = available
        self.transcript = transcript
    }

    func isAvailable(for localeIdentifier: String) async -> Bool {
        available
    }

    func requiresSpeechRecognitionAuthorization(for localeIdentifier: String) async -> Bool {
        requiresAuthorization
    }

    func makeStreamingSession(localeIdentifier: String) async -> (any StreamingSpeechTranscriptionSession)? {
        streamingSession
    }

    func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String {
        transcribeCallCount += 1
        if let transcriptionError {
            throw transcriptionError
        }
        return transcript
    }
}

@MainActor
final class MockFallbackSpeechEngine: FallbackSpeechTranscriptionEngine {
    var prepared: Bool
    var transcript: String
    var transcriptionError: Error?
    var invalidateWhenTranscriptionFails = false
    var preloadCallCount = 0
    var transcribeCallCount = 0

    init(prepared: Bool, transcript: String) {
        self.prepared = prepared
        self.transcript = transcript
    }

    func isAvailable(for localeIdentifier: String) async -> Bool {
        true
    }

    func preload() async throws {
        prepared = true
        preloadCallCount += 1
    }

    func isPrepared() async -> Bool {
        prepared
    }

    func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String {
        transcribeCallCount += 1
        if let transcriptionError {
            if invalidateWhenTranscriptionFails {
                prepared = false
            }
            throw transcriptionError
        }
        return transcript
    }
}

final class MockStreamingSpeechSession: StreamingSpeechTranscriptionSession, @unchecked Sendable {
    var transcript: String
    var finishError: Error?
    private(set) var appendedBytes = 0
    private(set) var finishCallCount = 0
    private(set) var cancelCallCount = 0

    init(transcript: String) {
        self.transcript = transcript
    }

    func appendPCM16(_ data: Data) {
        appendedBytes += data.count
    }

    func finish() async throws -> String {
        finishCallCount += 1
        if let finishError {
            throw finishError
        }
        return transcript
    }

    func cancel() {
        cancelCallCount += 1
    }
}

private enum MockTranscriptionError: LocalizedError {
    case failed

    var errorDescription: String? { "mock transcription failure" }
}

@MainActor
final class VoiceModelStoreTests: XCTestCase {
    func testAppleOnDeviceAvailableUsesAppleEngineOnly() async throws {
        let apple = MockSpeechEngine(available: true, transcript: "apple transcript")
        let fallback = MockFallbackSpeechEngine(prepared: false, transcript: "fallback transcript")
        let store = VoiceModelStore(appleEngine: apple, fallbackEngine: fallback)

        let transcript = try await store.transcribe(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            localeIdentifier: "en_US"
        )

        XCTAssertEqual(transcript, "apple transcript")
        XCTAssertEqual(apple.transcribeCallCount, 1)
        XCTAssertEqual(fallback.transcribeCallCount, 0)
    }

    func testAppleUnavailableUsesPreparedWhisperFallback() async throws {
        let apple = MockSpeechEngine(available: false, transcript: "apple transcript")
        let fallback = MockFallbackSpeechEngine(prepared: true, transcript: "fallback transcript")
        let store = VoiceModelStore(appleEngine: apple, fallbackEngine: fallback)

        let transcript = try await store.transcribe(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            localeIdentifier: "it_IT"
        )

        XCTAssertEqual(transcript, "fallback transcript")
        XCTAssertEqual(apple.transcribeCallCount, 0)
        XCTAssertEqual(fallback.transcribeCallCount, 1)
        XCTAssertEqual(store.status.state, .loaded)
    }

    func testAppleUnavailableWithoutFallbackReturnsDownloadPrompt() async {
        let apple = MockSpeechEngine(available: false, transcript: "apple transcript")
        let fallback = MockFallbackSpeechEngine(prepared: false, transcript: "fallback transcript")
        let store = VoiceModelStore(appleEngine: apple, fallbackEngine: fallback)

        do {
            _ = try await store.transcribe(
                audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
                localeIdentifier: "it_IT"
            )
            XCTFail("Expected transcription to fail without fallback model")
        } catch let failure as RewriteFailure {
            guard case .transcriptionUnavailable(let message) = failure else {
                return XCTFail("Unexpected failure: \(failure)")
            }
            XCTAssertTrue(message.contains("Download the Whisper fallback model"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPreparedFallbackSetsInitialLoadedStatus() async throws {
        let apple = MockSpeechEngine(available: false, transcript: "apple transcript")
        let fallback = MockFallbackSpeechEngine(prepared: true, transcript: "fallback transcript")
        let store = VoiceModelStore(appleEngine: apple, fallbackEngine: fallback)

        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(store.status.state, .loaded)
    }

    func testAppleFailureUsesPreparedWhisperFallback() async throws {
        let apple = MockSpeechEngine(available: true, transcript: "apple transcript")
        apple.transcriptionError = MockTranscriptionError.failed
        let fallback = MockFallbackSpeechEngine(prepared: true, transcript: "fallback transcript")
        let store = VoiceModelStore(appleEngine: apple, fallbackEngine: fallback)

        let transcript = try await store.transcribe(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            localeIdentifier: "en_US"
        )

        XCTAssertEqual(transcript, "fallback transcript")
        XCTAssertEqual(apple.transcribeCallCount, 1)
        XCTAssertEqual(fallback.transcribeCallCount, 1)
    }

    func testWhisperRouteSkipsAvailableAppleEngine() async throws {
        let apple = MockSpeechEngine(available: true, transcript: "apple transcript")
        let fallback = MockFallbackSpeechEngine(prepared: true, transcript: "fallback transcript")
        let store = VoiceModelStore(appleEngine: apple, fallbackEngine: fallback)

        let transcript = try await store.transcribe(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            localeIdentifier: "en_US",
            route: .whisper
        )

        XCTAssertEqual(transcript, "fallback transcript")
        XCTAssertEqual(apple.transcribeCallCount, 0)
        XCTAssertEqual(fallback.transcribeCallCount, 1)
    }

    func testStreamingTranscriptIsPreferredOverFileTranscription() async throws {
        let apple = MockSpeechEngine(available: true, transcript: "file transcript")
        let fallback = MockFallbackSpeechEngine(prepared: true, transcript: "fallback transcript")
        let session = MockStreamingSpeechSession(transcript: "streaming transcript")
        let store = VoiceModelStore(appleEngine: apple, fallbackEngine: fallback)

        let transcript = try await store.transcribe(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            localeIdentifier: "en_US",
            route: .apple(requiresSpeechRecognitionAuthorization: false),
            streamingSession: session
        )

        XCTAssertEqual(transcript, "streaming transcript")
        XCTAssertEqual(session.finishCallCount, 1)
        XCTAssertEqual(apple.transcribeCallCount, 0)
        XCTAssertEqual(fallback.transcribeCallCount, 0)
    }

    func testStreamingFailureFallsBackToAppleFileTranscription() async throws {
        let apple = MockSpeechEngine(available: true, transcript: "file transcript")
        let fallback = MockFallbackSpeechEngine(prepared: true, transcript: "fallback transcript")
        let session = MockStreamingSpeechSession(transcript: "streaming transcript")
        session.finishError = MockTranscriptionError.failed
        let store = VoiceModelStore(appleEngine: apple, fallbackEngine: fallback)

        let transcript = try await store.transcribe(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            localeIdentifier: "en_US",
            route: .apple(requiresSpeechRecognitionAuthorization: false),
            streamingSession: session
        )

        XCTAssertEqual(transcript, "file transcript")
        XCTAssertEqual(session.cancelCallCount, 1)
        XCTAssertEqual(apple.transcribeCallCount, 1)
        XCTAssertEqual(fallback.transcribeCallCount, 0)
    }

    func testRouteReportsWhetherSpeechAuthorizationIsRequired() async throws {
        let apple = MockSpeechEngine(available: true, transcript: "apple transcript")
        apple.requiresAuthorization = false
        let fallback = MockFallbackSpeechEngine(prepared: false, transcript: "fallback transcript")
        let store = VoiceModelStore(appleEngine: apple, fallbackEngine: fallback)

        let route = try await store.resolveRoute(for: "en_US")

        XCTAssertEqual(route, .apple(requiresSpeechRecognitionAuthorization: false))
    }

    func testWhisperLanguageCodeUsesLocaleLanguage() {
        XCTAssertEqual(WhisperKitSpeechEngine.whisperLanguageCode(for: "it_IT"), "it")
        XCTAssertEqual(WhisperKitSpeechEngine.whisperLanguageCode(for: "en-US"), "en")
        XCTAssertNil(WhisperKitSpeechEngine.whisperLanguageCode(for: "und"))
    }

    func testInvalidFallbackCacheReturnsStatusToNotDownloaded() async {
        let apple = MockSpeechEngine(available: false, transcript: "apple transcript")
        let fallback = MockFallbackSpeechEngine(prepared: true, transcript: "fallback transcript")
        fallback.transcriptionError = MockTranscriptionError.failed
        fallback.invalidateWhenTranscriptionFails = true
        let store = VoiceModelStore(appleEngine: apple, fallbackEngine: fallback)

        do {
            _ = try await store.transcribe(
                audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
                localeIdentifier: "en_US",
                route: .whisper
            )
            XCTFail("Expected invalid fallback cache to fail")
        } catch {
            XCTAssertEqual(store.status.state, .notDownloaded)
            XCTAssertNotNil(store.status.errorMessage)
        }
    }
}
