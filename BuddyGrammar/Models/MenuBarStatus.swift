import Foundation
import Observation

enum MenuBarStatusPhase: Equatable, Sendable {
    case idle
    case capture(profileName: String)
    case recording
    case transcribing
    case sending(profileName: String)
    case success(message: String)
    case failure(message: String)

    var title: String {
        switch self {
        case .idle:
            ""
        case .capture:
            "Reading..."
        case .recording:
            "Listening..."
        case .transcribing:
            "Transcribing..."
        case .sending:
            "Fixing..."
        case .success:
            "Done"
        case .failure:
            "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "text.redaction"
        case .capture:
            "text.cursor"
        case .recording:
            "waveform"
        case .transcribing:
            "waveform.and.magnifyingglass"
        case .sending:
            "wand.and.stars"
        case .success:
            "checkmark.circle.fill"
        case .failure:
            "exclamationmark.triangle.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle:
            "BuddyWrite"
        case .capture(let profileName):
            "BuddyWrite is reading text for \(profileName)."
        case .recording:
            "BuddyWrite is recording dictation."
        case .transcribing:
            "BuddyWrite is transcribing your speech locally."
        case .sending(let profileName):
            "BuddyWrite is rewriting text with \(profileName)."
        case .success(let message):
            "BuddyWrite finished. \(message)"
        case .failure(let message):
            "BuddyWrite error. \(message)"
        }
    }
}

@MainActor
@Observable
final class MenuBarStatusModel {
    var phase: MenuBarStatusPhase = .idle

    private var resetTask: Task<Void, Never>?

    func show(_ phase: MenuBarStatusPhase) {
        resetTask?.cancel()
        resetTask = nil
        self.phase = phase
    }

    func reset(after delay: Duration? = nil) {
        resetTask?.cancel()
        resetTask = nil

        guard let delay else {
            phase = .idle
            return
        }

        resetTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            phase = .idle
            resetTask = nil
        }
    }
}
