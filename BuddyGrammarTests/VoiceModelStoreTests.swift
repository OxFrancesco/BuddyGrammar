@testable import BuddyGrammar
import XCTest

@MainActor
final class MockSpeechEngine: SpeechTranscriptionEngine {
    var available: Bool
    var transcript: String
    var transcribeCallCount = 0

    init(available: Bool, transcript: String) {
        self.available = available
        self.transcript = transcript
    }

    func isAvailable(for localeIdentifier: String) async -> Bool {
        available
    }

    func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String {
        transcribeCallCount += 1
        return transcript
    }
}

@MainActor
final class MockFallbackSpeechEngine: FallbackSpeechTranscriptionEngine {
    var prepared: Bool
    var transcript: String
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
        return transcript
    }
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
}
