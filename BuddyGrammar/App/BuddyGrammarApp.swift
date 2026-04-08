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

        Window("Settings", id: AppModel.settingsWindowID) {
            SettingsView(model: model)
                .frame(minWidth: 660, minHeight: 460)
                .onAppear {
                    model.settingsWindowDidAppear()
                }
                .onDisappear {
                    model.settingsWindowDidDisappear()
                }
        }
        .defaultSize(width: 820, height: 560)
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}
