import ActivityKit
import BuddyGrammarKit
import SwiftUI
import WidgetKit

@main
struct BuddyGrammarLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        QuickDictationLiveActivity()
    }
}

struct QuickDictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: QuickDictationActivityAttributes.self) { context in
            LockScreenDictationView(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(statusColor(for: context.state.phase))
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(title(for: context.state.phase))
                            .font(.headline)
                        Text(detail(for: context.state.phase))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let startedAt = context.state.startedAt,
                       context.state.phase == .recording {
                        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                            .font(.caption.monospacedDigit())
                            .frame(maxWidth: 54)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(footer(for: context.state.phase))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(statusColor(for: context.state.phase))
                    .accessibilityLabel(title(for: context.state.phase))
            } compactTrailing: {
                if context.state.phase == .recording,
                   let startedAt = context.state.startedAt {
                    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                        .font(.caption2.monospacedDigit())
                        .frame(maxWidth: 38)
                } else {
                    Image(systemName: compactSymbol(for: context.state.phase))
                        .foregroundStyle(statusColor(for: context.state.phase))
                        .accessibilityHidden(true)
                }
            } minimal: {
                Image(systemName: compactSymbol(for: context.state.phase))
                    .foregroundStyle(statusColor(for: context.state.phase))
                    .accessibilityLabel(title(for: context.state.phase))
            }
            .keylineTint(statusColor(for: context.state.phase))
        }
    }
}

private struct LockScreenDictationView: View {
    let state: QuickDictationActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(statusColor(for: state.phase))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: state.phase))
                    .font(.headline)
                Text(detail(for: state.phase))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if state.phase == .recording, let startedAt = state.startedAt {
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                    .font(.body.monospacedDigit())
                    .frame(maxWidth: 70)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

private func title(
    for phase: QuickDictationActivityAttributes.ContentState.Phase
) -> String {
    switch phase {
    case .ready: "BuddyGrammar is ready"
    case .recording: "Listening"
    case .processing: "Preparing your text"
    }
}

private func detail(
    for phase: QuickDictationActivityAttributes.ContentState.Phase
) -> String {
    switch phase {
    case .ready: "Microphone ready for keyboard dictation"
    case .recording: "Stop from the BuddyGrammar keyboard when done"
    case .processing: "Transcribing and correcting"
    }
}

private func footer(
    for phase: QuickDictationActivityAttributes.ContentState.Phase
) -> String {
    switch phase {
    case .ready:
        "Tap the BuddyGrammar mic in any enabled keyboard to dictate."
    case .recording:
        "Keep talking in any app. Stop from the BuddyGrammar keyboard to insert your words."
    case .processing:
        "Your transcript will appear in the BuddyGrammar keyboard in a moment."
    }
}

private func compactSymbol(
    for phase: QuickDictationActivityAttributes.ContentState.Phase
) -> String {
    switch phase {
    case .ready: "mic.fill"
    case .recording: "waveform"
    case .processing: "ellipsis"
    }
}

private func statusColor(
    for phase: QuickDictationActivityAttributes.ContentState.Phase
) -> Color {
    switch phase {
    case .ready: .cyan
    case .recording: .red
    case .processing: .yellow
    }
}
