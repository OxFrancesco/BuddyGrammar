import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var bootstrapModel: AppModel?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.bootstrapModel?.start()
    }
}
