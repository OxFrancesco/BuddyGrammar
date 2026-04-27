import AVFoundation
import AppKit
import Foundation
import Speech

enum VoicePermissionState: String, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized

    var isAuthorized: Bool {
        self == .authorized
    }

    var title: String {
        switch self {
        case .notDetermined:
            "Not requested"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        case .authorized:
            "Granted"
        }
    }
}

@MainActor
protocol VoiceAuthorizing: AnyObject {
    var microphonePermission: VoicePermissionState { get }
    var speechRecognitionPermission: VoicePermissionState { get }
    func requestMicrophoneAccess() async -> Bool
    func requestSpeechRecognitionAccess() async -> Bool
    func openMicrophoneSettings()
    func openSpeechRecognitionSettings()
}

@MainActor
final class VoiceAuthorizationService: VoiceAuthorizing {
    var microphonePermission: VoicePermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            .notDetermined
        case .denied:
            .denied
        case .granted:
            .authorized
        @unknown default:
            .denied
        }
    }

    var speechRecognitionPermission: VoicePermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .authorized:
            .authorized
        @unknown default:
            .denied
        }
    }

    func requestMicrophoneAccess() async -> Bool {
        if microphonePermission.isAuthorized {
            return true
        }

        activateForPrivacyPrompt()
        return await Self.requestSystemMicrophoneAccess()
    }

    func requestSpeechRecognitionAccess() async -> Bool {
        if speechRecognitionPermission.isAuthorized {
            return true
        }

        activateForPrivacyPrompt()
        return await Self.requestSystemSpeechRecognitionAccess()
    }

    func openMicrophoneSettings() {
        openPrivacySettings(anchor: "Privacy_Microphone")
    }

    func openSpeechRecognitionSettings() {
        openPrivacySettings(anchor: "Privacy_SpeechRecognition")
    }

    private func openPrivacySettings(anchor: String) {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ]

        for candidate in urls {
            guard let url = URL(string: candidate) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func activateForPrivacyPrompt() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private nonisolated static func requestSystemMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { @Sendable granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private nonisolated static func requestSystemSpeechRecognitionAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
