import SwiftUI

struct MenuBarContentView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    private var fg: Color { colorScheme == .dark ? Color(hex: 0xCDD6F4) : Color(hex: 0x4C4F69) }
    private var fgSecondary: Color { colorScheme == .dark ? Color(hex: 0xA6ADC8) : Color(hex: 0x6C6F85) }
    private var bg: Color { colorScheme == .dark ? Color(hex: 0x1E1E2E) : .white }
    private var dividerColor: Color { colorScheme == .dark ? Color(hex: 0x313244) : Color(hex: 0xBCC0CC) }
    private var hoverBg: Color { colorScheme == .dark ? Color(hex: 0x313244) : Color(hex: 0xDCE0E8) }
    private var primary: Color { colorScheme == .dark ? Color(hex: 0xCBA6F7) : Color(hex: 0x8839EF) }
    private var green: Color { colorScheme == .dark ? Color(hex: 0xA6E3A1) : Color(hex: 0x40A02B) }
    private var orange: Color { colorScheme == .dark ? Color(hex: 0xFAB387) : Color(hex: 0xFE640B) }
    private var red: Color { colorScheme == .dark ? Color(hex: 0xF38BA8) : Color(hex: 0xD20F39) }
    private var appIconImage: NSImage { NSApplication.shared.applicationIconImage }

    var body: some View {
        ZStack {
            bg
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    Image(nsImage: appIconImage)
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text("BuddyWrite")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(fg)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

                neoDivider

                // Profiles
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.settingsStore.profiles) { profile in
                        ProfileButton(
                            profile: profile,
                            fg: fg,
                            fgSecondary: fgSecondary,
                            primary: primary,
                            hoverBg: hoverBg
                        ) {
                            model.runProfile(profile)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)

                if model.rewriteCoordinator.lastErrorMessage != nil {
                    neoDivider
                    Text(model.rewriteCoordinator.statusMessage)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(red)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }

                neoDivider

                LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 10) {
                    neoMenuButton(
                        model.voiceInputCoordinator.isRecording ? "Stop Dictation" : "Dictate with BuddyWrite",
                        icon: model.voiceInputCoordinator.isRecording ? "stop.circle.fill" : "mic.fill"
                    ) {
                        model.toggleVoiceInput()
                    }
                    neoMenuButton("Check for Updates", icon: "arrow.trianglehead.clockwise") {
                        model.checkForUpdates()
                    }
                    neoMenuButton("Open Settings", icon: "gearshape.fill") {
                        model.prepareToOpenSettingsWindow()
                        openWindow(id: AppModel.settingsWindowID)
                    }
                    neoMenuButton("Quit BuddyWrite", icon: "xmark.circle") {
                        NSApp.terminate(nil)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(bg)
            )
        }
        .padding(12)
        .frame(width: 452)
    }

    private var actionColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10)
        ]
    }

    private var neoDivider: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func neoMenuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        MenuActionButton(
            title: title,
            icon: icon,
            fg: fgSecondary,
            hoverBg: hoverBg,
            action: action
        )
    }
}

private struct MenuActionButton: View {
    let title: String
    let icon: String
    let fg: Color
    let hoverBg: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .foregroundStyle(fg)
            .background(isHovered ? hoverBg : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isHovered ? hoverBg.opacity(0.45) : fg.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
    }
}

// Extracted to get @State hover tracking per-row
private struct ProfileButton: View {
    let profile: PromptProfile
    let fg: Color
    let fgSecondary: Color
    let primary: Color
    let hoverBg: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(primary)
                Text(profile.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(fg)
                Spacer()
                Text(profile.hotkey?.displayString ?? "—")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(fgSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? hoverBg : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!profile.isEnabled)
        .opacity(profile.isEnabled ? 1 : 0.4)
        .onHover { isHovered = $0 }
    }
}
