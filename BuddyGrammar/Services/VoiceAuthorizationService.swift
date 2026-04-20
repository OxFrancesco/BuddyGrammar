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
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
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

        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func requestSpeechRecognitionAccess() async -> Bool {
        if speechRecognitionPermission.isAuthorized {
            return true
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func openMicrophoneSettings() {
        openPrivacySettings(anchor: "Privacy_Microphone")
    }

    func openSpeechRecognitionSettings() {
        openPrivacySettings(anchor: "Privacy_SpeechRecognition")
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
