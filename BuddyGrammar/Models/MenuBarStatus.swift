import Foundation
import Observation

enum MenuBarStatusPhase: Equatable, Sendable {
    case idle
    case capture(profileName: String)
    case sending(profileName: String)
    case success(message: String)
    case failure(message: String)

    var title: String {
        switch self {
        case .idle:
            ""
        case .capture:
            "Reading..."
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
            "BuddyGrammar"
        case .capture(let profileName):
            "BuddyGrammar is reading text for \(profileName)."
        case .sending(let profileName):
            "BuddyGrammar is rewriting text with \(profileName)."
        case .success(let message):
            "BuddyGrammar finished. \(message)"
        case .failure(let message):
            "BuddyGrammar error. \(message)"
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
