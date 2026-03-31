import SwiftUI

struct OverlayView: View {
    @Bindable var model: OverlayModel
    let motionMode: OverlayMotionMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldReduceMotion: Bool {
        switch motionMode {
        case .followSystem:
            reduceMotion
        case .reduce:
            true
        case .full:
            false
        }
    }

    var body: some View {
        ZStack {
            if model.isVisible {
                content
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(shouldReduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.82), value: model.animationTick)
            }
        }
        .frame(width: 360, height: 92)
        .padding(.top, 6)
    }

    private var content: some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(model.phase.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(model.phase.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if case .sending = model.phase, !shouldReduceMotion {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black.opacity(0.82))
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
                if case .sending = model.phase, !shouldReduceMotion {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.13),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: shimmerOffset)
                        .mask {
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                        }
                        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: model.animationTick)
                }
            }
        )
        .compositingGroup()
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }

    @ViewBuilder
    private var icon: some View {
        switch model.phase {
        case .capture:
            Image(systemName: "text.cursor")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        case .sending:
            Image(systemName: "wand.and.stars")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, options: shouldReduceMotion ? .default : .repeating, value: model.animationTick)
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.red)
        case .hidden:
            EmptyView()
        }
    }

    private var shimmerOffset: CGFloat {
        shouldReduceMotion ? 0 : 240
    }
}
