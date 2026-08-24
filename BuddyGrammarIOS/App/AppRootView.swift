import BuddyGrammarKit
import SwiftUI

struct AppRootView: View {
    @Bindable var model: IOSAppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.settings.hasCompletedOnboarding {
                MainTabView(model: model)
            } else {
                OnboardingView(model: model)
            }
        }
        .tint(.buddyAccent)
        .task {
            model.refresh()
        }
        .onOpenURL { url in
            guard let sessionID = KeyboardDictationHandoff.sessionID(from: url) else { return }
            model.handleKeyboardDictationHandoff(sessionID: sessionID)
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay(alignment: .top) {
            if let notice = model.notice {
                NoticeBanner(notice: notice)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.notice)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            model.refresh()
        }
    }
}

private struct MainTabView: View {
    @Bindable var model: IOSAppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack {
                    HomeView(model: model)
                }
            }

            Tab("Dictate", systemImage: "waveform", value: AppTab.dictation) {
                NavigationStack {
                    DictationView(model: model)
                }
            }

            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack {
                    SettingsView(model: model)
                }
            }
        }
    }
}
