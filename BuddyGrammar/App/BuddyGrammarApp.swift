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
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            MenuBarStatusLabel(status: model.menuBarStatus)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 660, minHeight: 460)
                .onAppear {
                    DispatchQueue.main.async {
                        for window in NSApp.windows where window.title.contains("Settings") || window.title.contains("Preferences") {
                            window.styleMask.insert(.resizable)
                            window.collectionBehavior.insert(.fullScreenPrimary)
                        }
                    }
                }
        }
    }
}
