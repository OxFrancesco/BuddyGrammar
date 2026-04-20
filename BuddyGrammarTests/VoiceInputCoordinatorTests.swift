@testable import BuddyGrammar
import Foundation
import XCTest

@MainActor
final class MockVoiceAuthorizationService: VoiceAuthorizing {
    var microphonePermission: VoicePermissionState = .authorized
    var speechRecognitionPermission: VoicePermissionState = .authorized
    var microphoneRequestResult = true
    var speechRequestResult = true

    func requestMicrophoneAccess() async -> Bool {
        microphonePermission = microphoneRequestResult ? .authorized : .denied
        return microphoneRequestResult
    }

    func requestSpeechRecognitionAccess() async -> Bool {
        speechRecognitionPermission = speechRequestResult ? .authorized : .denied
        return speechRequestResult
    }

    func openMicrophoneSettings() {}
    func openSpeechRecognitionSettings() {}
}

@MainActor
final class MockAudioRecordingService: AudioRecording {
    var isRecording = false
    var stopURL = URL(fileURLWithPath: "/tmp/buddywrite-voice-test.m4a")
    var startCallCount = 0
    var stopCallCount = 0

    func startRecording() throws {
        startCallCount += 1
        isRecording = true
    }

    func stopRecording() -> URL? {
        stopCallCount += 1
        isRecording = false
        return stopURL
    }
}

@MainActor
final class MockVoiceSettingsProvider: VoiceSettingsProviding {
    var appSettings: AppSettings
    var profiles: [PromptProfile]

    init(appSettings: AppSettings, profiles: [PromptProfile]) {
        self.appSettings = appSettings
        self.profiles = profiles
    }

    func profile(id: UUID) -> PromptProfile? {
        profiles.first { $0.id == id }
    }
}

@MainActor
final class MockRewriteProvider: TextRewriting {
    var nextRewrittenText = "rewritten"
    var lastRequest: RewriteRequest?

    func rewrite(_ request: RewriteRequest) async throws -> RewriteResult {
        lastRequest = request
        return RewriteResult(originalText: request.selectedText, rewrittenText: nextRewrittenText)
    }
}

final class MockClipboardWriter: ClipboardWriting {
    var snapshotValue = ClipboardSnapshot(items: [])
    var writtenStrings: [String] = []
    var restoreCallCount = 0

    func snapshot() -> ClipboardSnapshot {
        snapshotValue
    }

    func writeString(_ string: String) {
        writtenStrings.append(string)
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        restoreCallCount += 1
    }
}

@MainActor
final class MockPasteSimulator: PasteSimulating {
    var pasteCallCount = 0

    func simulatePaste() throws {
        pasteCallCount += 1
    }
}

@MainActor
final class MockAccessibilityService: AccessibilityChecking {
    var trusted = true

    func isTrusted(prompt: Bool) -> Bool {
        trusted
    }
}

@MainActor
final class VoiceInputCoordinatorTests: XCTestCase {
    private func makeCoordinator(
        outputMode: OutputMode = .copyToClipboard,
        microphoneGranted: Bool = true,
        speechGranted: Bool = true,
        accessibilityTrusted: Bool = true,
        appleAvailable: Bool = true,
        fallbackPrepared: Bool = false,
        transcript: String = "hello from voice",
        rewrittenText: String = "Hello from voice."
    ) -> (
        coordinator: VoiceInputCoordinator,
        authorization: MockVoiceAuthorizationService,
        recorder: MockAudioRecordingService,
        rewriteProvider: MockRewriteProvider,
        clipboard: MockClipboardWriter,
        pasteSimulator: MockPasteSimulator,
        accessibility: MockAccessibilityService
    ) {
        let settings = AppSettings(
            outputMode: outputMode,
            rewriteProvider: .openRouter(modelID: OpenRouterModel.defaultID),
            selectedLocalModel: .qwen3_4b_instruct_2507_4bit,
            preloadLocalModelOnLaunch: true,
            voiceProfileID: PromptProfile.grammarProfileID,
            voiceLocaleIdentifier: "en_US",
            voiceHotkey: nil,
            launchAtLogin: false,
            hasCompletedOnboarding: true
        )
        let settingsProvider = MockVoiceSettingsProvider(appSettings: settings, profiles: [PromptProfile.standard])
        let rewriteProvider = MockRewriteProvider()
        rewriteProvider.nextRewrittenText = rewrittenText
        let clipboard = MockClipboardWriter()
        let pasteSimulator = MockPasteSimulator()
        let authorization = MockVoiceAuthorizationService()
        authorization.microphoneRequestResult = microphoneGranted
        authorization.speechRequestResult = speechGranted
        let recorder = MockAudioRecordingService()
        let accessibility = MockAccessibilityService()
        accessibility.trusted = accessibilityTrusted
        let menuBarStatus = MenuBarStatusModel()
        let apple = MockSpeechEngine(available: appleAvailable, transcript: transcript)
        let fallback = MockFallbackSpeechEngine(prepared: fallbackPrepared, transcript: transcript)
        let voiceStore = VoiceModelStore(appleEngine: apple, fallbackEngine: fallback)
        let coordinator = VoiceInputCoordinator(
            settingsProvider: settingsProvider,
            rewriteProvider: rewriteProvider,
            clipboardService: clipboard,
            eventSimulationService: pasteSimulator,
            voiceAuthorizationService: authorization,
            audioRecordingService: recorder,
            voiceModelStore: voiceStore,
            menuBarStatus: menuBarStatus
        )

        return (coordinator, authorization, recorder, rewriteProvider, clipboard, pasteSimulator, accessibility)
    }

    func testStartAndStopRecordingTransitions() async throws {
        let harness = makeCoordinator()

        harness.coordinator.toggleDictation(accessibilityService: harness.accessibility)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(harness.coordinator.isRecording)

        harness.coordinator.toggleDictation(accessibilityService: harness.accessibility)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(harness.coordinator.isRecording)
        XCTAssertEqual(harness.recorder.startCallCount, 1)
        XCTAssertEqual(harness.recorder.stopCallCount, 1)
    }

    func testBusyStateRejection() {
        let harness = makeCoordinator()
        harness.coordinator.isProcessing = true

        harness.coordinator.toggleDictation(accessibilityService: harness.accessibility)

        XCTAssertEqual(harness.coordinator.lastErrorMessage, RewriteFailure.busy.errorDescription)
    }

    func testPermissionDeniedPath() async throws {
        let harness = makeCoordinator(microphoneGranted: false)

        harness.coordinator.toggleDictation(accessibilityService: harness.accessibility)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(harness.coordinator.isRecording)
        XCTAssertEqual(harness.coordinator.lastErrorMessage, RewriteFailure.microphonePermissionDenied.errorDescription)
    }

    func testTranscriptRewriteReplaceSelectionFlow() async throws {
        let harness = makeCoordinator(outputMode: .replaceSelection)

        harness.coordinator.toggleDictation(accessibilityService: harness.accessibility)
        try await Task.sleep(for: .milliseconds(50))
        harness.coordinator.toggleDictation(accessibilityService: harness.accessibility)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(harness.rewriteProvider.lastRequest?.selectedText, "hello from voice")
        XCTAssertEqual(harness.clipboard.writtenStrings.last, "Hello from voice.")
        XCTAssertEqual(harness.pasteSimulator.pasteCallCount, 1)
        XCTAssertEqual(harness.clipboard.restoreCallCount, 1)
    }

    func testTranscriptRewriteCopyToClipboardFlow() async throws {
        let harness = makeCoordinator(outputMode: .copyToClipboard)

        harness.coordinator.toggleDictation(accessibilityService: harness.accessibility)
        try await Task.sleep(for: .milliseconds(50))
        harness.coordinator.toggleDictation(accessibilityService: harness.accessibility)
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(harness.rewriteProvider.lastRequest?.selectedText, "hello from voice")
        XCTAssertEqual(harness.clipboard.writtenStrings.last, "Hello from voice.")
        XCTAssertEqual(harness.pasteSimulator.pasteCallCount, 0)
    }
}
