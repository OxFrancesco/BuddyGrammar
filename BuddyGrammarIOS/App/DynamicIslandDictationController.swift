@preconcurrency import ActivityKit
import AVFAudio
import BuddyGrammarKit
import Foundation
import OSLog

private let dynamicIslandLog = Logger(
    subsystem: "com.francescooddo.BuddyGrammar",
    category: "dynamic-island-dictation"
)

enum DynamicIslandDictationError: LocalizedError {
    case activitiesDisabled
    case microphoneDenied
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .activitiesDisabled:
            "Live Activities are disabled for BuddyGrammar. Enable them in iPhone Settings and try again."
        case .microphoneDenied:
            "Microphone access is required. Enable it for BuddyGrammar in iPhone Settings."
        case .microphoneUnavailable:
            "BuddyGrammar could not keep the microphone ready on this device."
        }
    }
}

@MainActor
final class DynamicIslandDictationController {
    var onStartRequested: ((UUID) -> Void)?
    var onStopRequested: (() -> Void)?
    var onExpired: (() -> Void)?

    private(set) var isReady = false

    private let preferences: SharedPreferences?
    private let audioEngine = AVAudioEngine()
    private var activityID: String?
    private var signalObserver: DictationCompanionObserver?
    private var heartbeatTask: Task<Void, Never>?
    private var expirationTask: Task<Void, Never>?
    private var inputTapInstalled = false
    private var expirationDate: Date?

    init(preferences: SharedPreferences?) {
        self.preferences = preferences
        signalObserver = DictationCompanionObserver { [weak self] signal in
            Task { @MainActor [weak self] in
                self?.handle(signal)
            }
        }
    }

    func activate(
        duration: QuickDictationDuration,
        now: Date = .now
    ) async throws -> Date? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw DynamicIslandDictationError.activitiesDisabled
        }
        guard await requestMicrophonePermission() else {
            throw DynamicIslandDictationError.microphoneDenied
        }

        let expiresAt = duration.expirationDate(startedAt: now)
        do {
            try startReadinessAudio()
            expirationDate = expiresAt
            isReady = true
            startHeartbeat()
            scheduleExpiration(at: expiresAt)
            try await showActivity(
                state: .init(phase: .ready),
                activatedAt: now,
                staleDate: expiresAt
            )
            dynamicIslandLog.notice("Dynamic Island readiness started")
            return expiresAt
        } catch {
            await deactivate()
            throw error
        }
    }

    func restoreIfNeeded(settings: BuddyGrammarSettings, now: Date = .now) async {
        guard settings.enablesQuickDictation,
              settings.quickDictationExpiresAt.map({ $0 > now }) ?? true else {
            if settings.enablesQuickDictation {
                onExpired?()
            }
            await deactivate()
            return
        }
        guard !isReady, activityID == nil else { return }

        do {
            let expiresAt = settings.quickDictationExpiresAt
            try startReadinessAudio()
            expirationDate = expiresAt
            isReady = true
            startHeartbeat()
            scheduleExpiration(at: expiresAt)
            try await showActivity(
                state: .init(phase: .ready),
                activatedAt: now,
                staleDate: expiresAt
            )
        } catch {
            dynamicIslandLog.error("Could not restore readiness: \(error.localizedDescription, privacy: .public)")
            await deactivate()
        }
    }

    func prepareForRecording(startedAt: Date = .now) async {
        stopReadinessAudio(deactivateSession: false)
        await updateActivity(
            .init(phase: .recording, startedAt: startedAt),
            staleDate: expirationDate
        )
    }

    func showProcessing() async {
        await updateActivity(
            .init(phase: .processing),
            staleDate: expirationDate
        )
    }

    func resumeAfterRecording(settings: BuddyGrammarSettings, now: Date = .now) async {
        guard settings.enablesQuickDictation,
              settings.quickDictationExpiresAt.map({ $0 > now }) ?? true else {
            await deactivate()
            return
        }

        do {
            try startReadinessAudio()
            isReady = true
            startHeartbeat()
            await updateActivity(.init(phase: .ready), staleDate: expirationDate)
        } catch {
            dynamicIslandLog.error("Could not resume readiness: \(error.localizedDescription, privacy: .public)")
            await deactivate()
        }
    }

    func deactivate() async {
        expirationTask?.cancel()
        expirationTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        stopReadinessAudio(deactivateSession: true)
        isReady = false
        expirationDate = nil
        preferences?.clearCompanionHeartbeat()

        let activities = Activity<QuickDictationActivityAttributes>.activities
        activityID = nil
        for existingActivity in activities {
            await existingActivity.end(nil, dismissalPolicy: .immediate)
        }
        dynamicIslandLog.notice("Dynamic Island readiness stopped")
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startReadinessAudio() throws {
        guard !audioEngine.isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .record,
            mode: .measurement,
            options: [.allowBluetoothHFP]
        )
        try session.setActive(true)

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw DynamicIslandDictationError.microphoneUnavailable
        }
        if !inputTapInstalled {
            input.installTap(
                onBus: 0,
                bufferSize: 1_024,
                format: format,
                block: Self.discardReadinessAudio
            )
            inputTapInstalled = true
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stopReadinessAudio(deactivateSession: true)
            throw error
        }
    }

    private nonisolated static func discardReadinessAudio(
        _: AVAudioPCMBuffer,
        _: AVAudioTime
    ) {
        // AVFAudio invokes tap callbacks on a realtime queue, not MainActor.
        // Readiness audio is deliberately discarded. Only audio captured after
        // a keyboard mic tap is written to a recording file.
    }

    private func stopReadinessAudio(deactivateSession: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if inputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        audioEngine.reset()
        isReady = false
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }

    private func showActivity(
        state: QuickDictationActivityAttributes.ContentState,
        activatedAt: Date,
        staleDate: Date?
    ) async throws {
        for existingActivity in Activity<QuickDictationActivityAttributes>.activities {
            await existingActivity.end(nil, dismissalPolicy: .immediate)
        }
        let content = ActivityContent(state: state, staleDate: staleDate)
        let requestedActivity = try Activity.request(
            attributes: QuickDictationActivityAttributes(activatedAt: activatedAt),
            content: content,
            pushType: nil
        )
        activityID = requestedActivity.id
    }

    private func updateActivity(
        _ state: QuickDictationActivityAttributes.ContentState,
        staleDate: Date?
    ) async {
        guard let activityID,
              let activity = Activity<QuickDictationActivityAttributes>.activities.first(
                  where: { $0.id == activityID }
              ) else { return }
        await activity.update(ActivityContent(state: state, staleDate: staleDate))
    }

    private func startHeartbeat() {
        preferences?.recordCompanionHeartbeat()
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                preferences?.recordCompanionHeartbeat()
            }
        }
    }

    private func scheduleExpiration(at date: Date?) {
        expirationTask?.cancel()
        guard let date else {
            expirationTask = nil
            return
        }
        expirationTask = Task { [weak self] in
            let delay = max(0, date.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            onExpired?()
            await deactivate()
        }
    }

    private func handle(_ signal: DictationCompanionSignal) {
        switch signal {
        case .startRequested:
            guard isReady,
                  let session = preferences?.loadKeyboardDictationSession(),
                  session.phase == .launching else { return }
            onStartRequested?(session.id)
        case .stopRequested:
            onStopRequested?()
        }
    }
}
