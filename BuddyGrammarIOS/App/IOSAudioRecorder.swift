import AVFAudio
import Foundation

enum IOSAudioRecorderError: LocalizedError {
    case permissionDenied
    case unableToStart
    case noActiveRecording
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Microphone access is required for dictation. You can enable it in Settings."
        case .unableToStart:
            "The microphone could not start recording."
        case .noActiveRecording:
            "There is no active recording to finish."
        case .recordingFailed:
            "The recording stopped unexpectedly. Please try again."
        }
    }
}

@MainActor
final class IOSAudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var didFinishSuccessfully = true

    func start() async throws -> Date {
        let hasPermission = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard hasPermission else { throw IOSAudioRecorderError.permissionDenied }

        cancel()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .record,
            mode: .spokenAudio,
            options: [.allowBluetoothHFP, .duckOthers]
        )
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appending(path: "BuddyGrammar-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 96_000,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw IOSAudioRecorderError.unableToStart
        }

        didFinishSuccessfully = true
        self.recorder = recorder
        recordingURL = url
        return .now
    }

    func stop() throws -> URL {
        guard let recorder, let recordingURL else {
            throw IOSAudioRecorderError.noActiveRecording
        }

        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )

        guard didFinishSuccessfully,
              FileManager.default.fileExists(atPath: recordingURL.path) else {
            throw IOSAudioRecorderError.recordingFailed
        }
        return recordingURL
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            self?.didFinishSuccessfully = false
        }
    }
}
