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
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(nsImage: appIconImage)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text("BuddyGrammar")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(fg)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            neoDivider

            // Profiles
            VStack(alignment: .leading, spacing: 2) {
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
            .padding(.vertical, 4)
            .padding(.horizontal, 4)

            if model.rewriteCoordinator.lastErrorMessage != nil {
                neoDivider
                Text(model.rewriteCoordinator.statusMessage)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }

            neoDivider

            // Actions
            HStack(spacing: 10) {
                neoMenuButton("Updates", icon: "arrow.trianglehead.clockwise") { model.checkForUpdates() }
                neoMenuButton("Settings", icon: "gearshape") {
                    model.prepareToOpenSettingsWindow()
                    openWindow(id: AppModel.settingsWindowID)
                }
                Spacer()
                neoMenuButton("Quit", icon: "xmark.circle") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 260)
        .background(bg)
    }

    private var neoDivider: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)
            .padding(.horizontal, 10)
    }

    private func neoMenuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(fgSecondary)
        }
        .buttonStyle(.plain)
        .focusable(false)
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isHovered ? hoverBg : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!profile.isEnabled)
        .opacity(profile.isEnabled ? 1 : 0.4)
        .onHover { isHovered = $0 }
    }
}
