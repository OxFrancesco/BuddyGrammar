import SwiftUI

extension Color {
    static let buddyAccent = Color(red: 0.43, green: 0.25, blue: 0.91)
    static let buddyAccentSoft = Color(red: 0.91, green: 0.88, blue: 1.00)
}

struct AppBackground: View {
    var body: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
    }
}

/// The BuddyGrammar mark: five waveform bars. It echoes the keyboard's
/// dictation key and the companion window, and animates while recording.
struct WaveformMark: View {
    var isAnimating = false
    var tint: Color = .buddyAccent
    var barWidth: CGFloat = 6

    private static let restingHeights: [CGFloat] = [0.38, 0.72, 1.0, 0.58, 0.82]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.16, paused: !isAnimating)) { context in
            let beat = context.date.timeIntervalSinceReferenceDate * 6
            HStack(spacing: barWidth * 0.8) {
                ForEach(0..<5, id: \.self) { index in
                    let resting = Self.restingHeights[index]
                    let scale = isAnimating
                        ? 0.35 + 0.65 * abs(sin(beat + Double(index) * 1.1))
                        : resting
                    Capsule()
                        .fill(tint)
                        .frame(width: barWidth)
                        .scaleEffect(y: scale, anchor: .center)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: isAnimating)
        }
        .accessibilityHidden(true)
    }
}

struct AppCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.regularMaterial, in: .rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

struct StatusBadge: View {
    let title: String
    let isReady: Bool

    var body: some View {
        Label(title, systemImage: isReady ? "checkmark.circle.fill" : "circle.dashed")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isReady ? Color.green : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (isReady ? Color.green : Color.secondary).opacity(0.11),
                in: .capsule
            )
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(
                Color.buddyAccent.opacity(configuration.isPressed ? 0.78 : 1),
                in: .rect(cornerRadius: 16)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct NoticeBanner: View {
    let notice: AppNotice

    var body: some View {
        Label(
            notice.message,
            systemImage: notice.kind == .success ? "checkmark.circle.fill" : "info.circle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thickMaterial, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("app.notice")
    }
}
