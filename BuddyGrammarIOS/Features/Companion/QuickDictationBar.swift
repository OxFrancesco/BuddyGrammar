import SwiftUI

/// Embeds the companion's sample buffer layer in SwiftUI. The layer must stay
/// in the view hierarchy for Picture in Picture to start reliably, so this
/// view is installed at the app root while quick dictation is enabled.
struct CompanionLayerView: UIViewRepresentable {
    let controller: DictationCompanionController

    func makeUIView(context: Context) -> CompanionSampleBufferView {
        controller.layerHostView
    }

    func updateUIView(_ uiView: CompanionSampleBufferView, context: Context) {}
}

/// Floating bar shown while quick dictation is enabled. Hosts the PiP layer
/// preview and lets the user tuck the companion window away manually.
struct QuickDictationBar: View {
    let companion: DictationCompanionController

    var body: some View {
        HStack(spacing: 12) {
            CompanionLayerView(controller: companion)
                .frame(width: 64, height: 36)
                .background(Color.black, in: .rect(cornerRadius: 9))
                .clipShape(.rect(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Quick dictation")
                    .font(.caption.weight(.semibold))
                Text(
                    companion.isPictureInPictureActive
                        ? "Tucked away — dictate from any app"
                        : "Leave the app or tap to tuck away"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                companion.startPictureInPicture()
            } label: {
                Image(systemName: "pip.enter")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.buddyAccent.opacity(0.14), in: .circle)
            }
            .disabled(companion.isPictureInPictureActive)
            .accessibilityLabel("Tuck quick dictation away")
            .accessibilityIdentifier("companion.enterPip")
        }
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
        .accessibilityIdentifier("companion.bar")
    }
}
