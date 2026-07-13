import SwiftUI

struct KeyboardLabView: View {
    @State private var text = "i really enjoy writing with buddygrammar it makes everything easier"

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Try your keyboard", systemImage: "keyboard.fill")
                                .font(.title3.bold())
                                .foregroundStyle(Color.buddyAccent)
                            Text("Tap below, switch to BuddyGrammar with the globe key, then tap ★ to correct the sample.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 230)
                        .padding(14)
                        .scrollContentBackground(.hidden)
                        .background(.regularMaterial, in: .rect(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.buddyAccent.opacity(0.22), lineWidth: 1)
                        }
                        .accessibilityLabel("Keyboard testing text")
                        .accessibilityIdentifier("keyboardLab.input")

                    Button("Reset sample", systemImage: "arrow.counterclockwise") {
                        text = "i really enjoy writing with buddygrammar it makes everything easier"
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("keyboardLab.reset")
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Keyboard Lab")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("keyboardLab.screen")
    }
}
