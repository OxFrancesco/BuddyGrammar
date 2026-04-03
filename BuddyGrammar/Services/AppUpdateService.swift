import AppKit
import Foundation
import Sparkle

@MainActor
final class AppUpdateService {
    private let updaterController: SPUStandardUpdaterController?
    private let releasesURL = URL(string: "https://github.com/oxfrancesco/buddygrammar/releases")!

    init(bundle: Bundle = .main) {
        if Self.isSparkleConfigured(in: bundle) {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            updaterController = nil
        }
    }

    var currentVersionDescription: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(shortVersion) (\(buildVersion))"
    }

    var usesSparkleUpdates: Bool {
        updaterController != nil
    }

    func checkForUpdates() {
        if let updater = updaterController?.updater, updater.canCheckForUpdates {
            updater.checkForUpdates()
        } else {
            openReleasesPage()
        }
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(releasesURL)
    }

    private static func isSparkleConfigured(in bundle: Bundle) -> Bool {
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String

        return !(feedURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && !(publicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && publicKey != "__SPARKLE_PUBLIC_ED_KEY__"
    }
}
