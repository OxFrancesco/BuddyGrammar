import Foundation

enum OutputMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case replaceSelection
    case copyToClipboard

    var id: Self { self }

    var title: String {
        switch self {
        case .replaceSelection:
            "Replace Selected Text"
        case .copyToClipboard:
            "Copy To Clipboard"
        }
    }
}

enum OverlayMotionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case followSystem
    case reduce
    case full

    var id: Self { self }

    var title: String {
        switch self {
        case .followSystem:
            "Follow System"
        case .reduce:
            "Reduce Motion"
        case .full:
            "Full Motion"
        }
    }
}

struct AppSettings: Codable, Hashable, Sendable {
    var outputMode: OutputMode
    var launchAtLogin: Bool
    var overlayMotionMode: OverlayMotionMode
    var hasCompletedOnboarding: Bool

    static let `default` = AppSettings(
        outputMode: .replaceSelection,
        launchAtLogin: false,
        overlayMotionMode: .followSystem,
        hasCompletedOnboarding: false
    )
}
