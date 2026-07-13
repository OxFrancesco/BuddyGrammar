import Foundation
import XCTest
@testable import BuddyGrammarKit

final class LiveCloudIntegrationTests: XCTestCase {
    func testLiveOpenRouterCorrectionWhenConfigured() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let baseURLString = environment["BUDDYGRAMMAR_API_BASE_URL"],
              let baseURL = URL(string: baseURLString) else {
            throw XCTSkip("Set BUDDYGRAMMAR_API_BASE_URL to run the live service check.")
        }

        let result = try await OpenRouterCorrectionClient(
            endpoint: baseURL.appending(path: "v1/correct")
        ).correct(
            text: "this sentence have one error.",
            clientID: UUID(),
            modelID: environment["OPENROUTER_MODEL_ID"]
                ?? BuddyGrammarConfiguration.defaultOpenRouterModelID,
            instruction: BuddyGrammarConfiguration.standardCorrectionInstruction
        )

        XCTAssertFalse(result.isEmpty)
        XCTAssertFalse(result.lowercased().hasPrefix("here is"))
    }

    func testLiveElevenLabsTranscriptionWhenConfigured() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let baseURLString = environment["BUDDYGRAMMAR_API_BASE_URL"],
              let baseURL = URL(string: baseURLString) else {
            throw XCTSkip("Set BUDDYGRAMMAR_API_BASE_URL to run the live service check.")
        }
        guard let audioPath = environment["BUDDYGRAMMAR_LIVE_AUDIO_FILE"], !audioPath.isEmpty else {
            throw XCTSkip("Set BUDDYGRAMMAR_LIVE_AUDIO_FILE to a spoken M4A fixture.")
        }

        let audioURL = URL(fileURLWithPath: audioPath)
        let result = try await ElevenLabsTranscriptionClient(
            endpoint: baseURL.appending(path: "v1/transcribe")
        ).transcribe(
            audioData: Data(contentsOf: audioURL),
            clientID: UUID()
        )

        XCTAssertFalse(result.text.isEmpty)
    }
}
