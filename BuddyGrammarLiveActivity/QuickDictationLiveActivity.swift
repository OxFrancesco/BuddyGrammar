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
                    Image(systemName: "keyboard.badge.ellipsis")
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
                DynamicIslandExpandedRegion(.trailing) { EmptyView() }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Use Apple Dictation for same-field input, or start a visible recording in BuddyGrammar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(statusColor(for: context.state.phase))
                    .accessibilityLabel(title(for: context.state.phase))
            } compactTrailing: {
                Image(systemName: compactSymbol(for: context.state.phase))
                    .foregroundStyle(statusColor(for: context.state.phase))
                    .accessibilityHidden(true)
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
            Image(systemName: "keyboard.badge.ellipsis")
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
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

private func title(
    for _: QuickDictationActivityAttributes.ContentState.Phase
) -> String {
    "Keyboard dictation session ended"
}

private func detail(
    for _: QuickDictationActivityAttributes.ContentState.Phase
) -> String {
    "Open BuddyGrammar to record, or use Apple Dictation from the system keyboard"
}

private func compactSymbol(
    for _: QuickDictationActivityAttributes.ContentState.Phase
) -> String {
    "keyboard.badge.ellipsis"
}

private func statusColor(
    for _: QuickDictationActivityAttributes.ContentState.Phase
) -> Color {
    .secondary
}
