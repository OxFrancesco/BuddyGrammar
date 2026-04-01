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

struct AppSettings: Codable, Hashable, Sendable {
    var outputMode: OutputMode
    var launchAtLogin: Bool
    var hasCompletedOnboarding: Bool

    static let `default` = AppSettings(
        outputMode: .replaceSelection,
        launchAtLogin: false,
        hasCompletedOnboarding: false
    )
}
