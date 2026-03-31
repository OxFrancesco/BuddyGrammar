import Foundation
import Observation

enum OverlayPhase: Equatable, Sendable {
    case hidden
    case capture(profileName: String)
    case sending(profileName: String)
    case success(profileName: String, message: String)
    case failure(message: String)

    var title: String {
        switch self {
        case .hidden:
            ""
        case .capture:
            "Reading Selection"
        case .sending(let profileName):
            profileName
        case .success(let profileName, _):
            profileName
        case .failure:
            "BuddyGrammar"
        }
    }

    var subtitle: String {
        switch self {
        case .hidden:
            ""
        case .capture:
            "Looking at the highlighted text"
        case .sending:
            "Fixing your text with OpenRouter"
        case .success(_, let message):
            message
        case .failure(let message):
            message
        }
    }
}

@MainActor
@Observable
final class OverlayModel {
    var phase: OverlayPhase = .hidden
    var isVisible = false
    var animationTick = 0

    func present(_ phase: OverlayPhase) {
        self.phase = phase
        isVisible = true
        animationTick &+= 1
    }

    func hide() {
        phase = .hidden
        isVisible = false
        animationTick &+= 1
    }
}
