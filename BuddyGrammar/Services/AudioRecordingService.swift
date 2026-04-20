import AVFoundation
import Foundation

@MainActor
protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    func startRecording() throws
    func stopRecording() -> URL?
}

@MainActor
final class AudioRecordingService: NSObject, AudioRecording {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    func startRecording() throws {
        guard !isRecording else { return }

        let outputURL = Self.makeOutputURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw RewriteFailure.voiceRecordingFailed("BuddyWrite could not start recording audio.")
        }

        self.recorder = recorder
        self.outputURL = outputURL
    }

    func stopRecording() -> URL? {
        guard let recorder, let outputURL else { return nil }
        recorder.stop()
        self.recorder = nil
        self.outputURL = nil
        return outputURL
    }

    private static func makeOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("buddywrite-dictation-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }
}
