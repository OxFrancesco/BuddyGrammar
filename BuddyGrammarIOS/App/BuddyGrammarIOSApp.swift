import SwiftUI

@main
struct BuddyGrammarIOSApp: App {
    @State private var model = IOSAppModel()

    var body: some Scene {
        WindowGroup {
            AppRootView(model: model)
        }
    }
}
