import SwiftUI

struct MenuBarContentView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    private var foreground: Color { colorScheme == .dark ? Color(hex: 0xCDD6F4) : Color(hex: 0x4C4F69) }
    private var secondary: Color { colorScheme == .dark ? Color(hex: 0xA6ADC8) : Color(hex: 0x6C6F85) }
    private var background: Color { colorScheme == .dark ? Color(hex: 0x1E1E2E) : Color(hex: 0xEFF1F5) }
    private var surface: Color { colorScheme == .dark ? Color(hex: 0x313244) : Color.white }
    private var hover: Color { colorScheme == .dark ? Color(hex: 0x45475A) : Color(hex: 0xDCE0E8) }
    private var primary: Color { colorScheme == .dark ? Color(hex: 0xCBA6F7) : Color(hex: 0x8839EF) }

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            personalities
            divider
            primaryActions
            divider
            utilityBar
        }
        .background(background)
        .foregroundStyle(foreground)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .clipShape(.rect(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text("BuddyWrite")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                Text(model.rewriteCoordinator.statusMessage)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(model.rewriteCoordinator.lastErrorMessage == nil ? secondary : NeoTheme.destructive)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if model.rewriteCoordinator.isProcessing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(NeoTheme.green)
                    .frame(width: 7, height: 7)
                    .overlay {
                        Circle().stroke(NeoTheme.green.opacity(0.25), lineWidth: 4)
                    }
                    .accessibilityLabel("Ready")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var personalities: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PERSONALITIES")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(secondary)
                .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(model.settingsStore.profiles) { profile in
                        MenuProfileRow(
                            profile: profile,
                            foreground: foreground,
                            secondary: secondary,
                            primary: primary,
                            hover: hover
                        ) {
                            model.runProfile(profile)
                        }
                    }
                }
            }
            .frame(maxHeight: 172)
        }
        .padding(10)
    }

    private var primaryActions: some View {
        VStack(spacing: 4) {
            MenuActionRow(
                title: model.voiceInputCoordinator.isRecording ? "Stop Dictation" : "Dictate",
                subtitle: model.voiceInputCoordinator.isRecording ? "Recording in progress" : "Local voice input",
                icon: model.voiceInputCoordinator.isRecording ? "stop.fill" : "mic.fill",
                tint: model.voiceInputCoordinator.isRecording ? NeoTheme.destructive : primary,
                foreground: foreground,
                secondary: secondary,
                hover: hover
            ) {
                model.toggleVoiceInput()
            }

            MenuActionRow(
                title: "Notes",
                subtitle: "Open your snippets",
                icon: "note.text",
                tint: primary,
                foreground: foreground,
                secondary: secondary,
                hover: hover
            ) {
                model.prepareToOpenUtilityWindow()
                openWindow(id: AppModel.notesWindowID)
            }
        }
        .padding(10)
    }

    private var utilityBar: some View {
        HStack(spacing: 6) {
            UtilityButton(title: "Settings", icon: "gearshape", foreground: secondary, hover: hover) {
                model.prepareToOpenSettingsWindow()
                openWindow(id: AppModel.settingsWindowID)
            }
            UtilityButton(title: "Updates", icon: "arrow.trianglehead.clockwise", foreground: secondary, hover: hover) {
                model.checkForUpdates()
            }
            #if DEBUG
            UtilityButton(title: "Debug", icon: "ladybug", foreground: secondary, hover: hover) {
                model.prepareToOpenUtilityWindow()
                openWindow(id: AppModel.debugWindowID)
            }
            #endif

            Spacer()

            UtilityButton(title: "Quit", icon: "power", foreground: secondary, hover: hover) {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(surface.opacity(colorScheme == .dark ? 0.28 : 0.55))
    }

    private var divider: some View {
        Rectangle()
            .fill(secondary.opacity(0.15))
            .frame(height: 1)
    }
}

private struct MenuProfileRow: View {
    let profile: PromptProfile
    let foreground: Color
    let secondary: Color
    let primary: Color
    let hover: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(primary)
                    .frame(width: 18)

                Text(profile.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(foreground)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let modelID = profile.openRouterModelID {
                    Text(modelID.split(separator: "/").last.map(String.init) ?? modelID)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 90, alignment: .trailing)
                }

                Text(profile.hotkey?.displayString ?? "—")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(secondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(isHovered ? hover : Color.clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!profile.isEnabled)
        .opacity(profile.isEnabled ? 1 : 0.42)
        .onHover { isHovered = $0 }
    }
}

private struct MenuActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let foreground: Color
    let secondary: Color
    let hover: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: .rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(foreground)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(secondary.opacity(0.65))
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .background(isHovered ? hover : Color.clear, in: .rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
    }
}

private struct UtilityButton: View {
    let title: String
    let icon: String
    let foreground: Color
    let hover: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 29, height: 25)
                .background(isHovered ? hover : Color.clear, in: .rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(title)
        .onHover { isHovered = $0 }
    }
}
