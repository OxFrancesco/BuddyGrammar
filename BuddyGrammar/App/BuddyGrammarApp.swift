import SwiftUI

@main
struct BuddyGrammarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model: AppModel

    init() {
        let model = AppModel()
        self.model = model
        AppDelegate.bootstrapModel = model
    }

    var body: some Scene {
        MenuBarExtra("BuddyGrammar", systemImage: "text.redaction") {
            MenuBarContentView(model: model)
        }

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 760, minHeight: 520)
        }
    }
}
