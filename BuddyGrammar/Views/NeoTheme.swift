import SwiftUI

// MARK: - Neobrutalist Theme

enum NeoTheme {
    static var background: Color {
        Color(nsColor: .init(name: nil) { appearance in
            appearance.isDark
                ? NSColor(red: 0x14/255, green: 0x14/255, blue: 0x14/255, alpha: 1)
                : NSColor(red: 0xFA/255, green: 0xFA/255, blue: 0xFA/255, alpha: 1)
        })
    }

    static var foreground: Color {
        Color(nsColor: .init(name: nil) { appearance in
            appearance.isDark
                ? NSColor(red: 0xF5/255, green: 0xF5/255, blue: 0xF5/255, alpha: 1)
                : NSColor(red: 0x1A/255, green: 0x1A/255, blue: 0x1A/255, alpha: 1)
        })
    }

    static var card: Color {
        Color(nsColor: .init(name: nil) { appearance in
            appearance.isDark
                ? NSColor(red: 0x1F/255, green: 0x1F/255, blue: 0x1F/255, alpha: 1)
                : NSColor.white
        })
    }

    static var primary: Color {
        Color(nsColor: .init(name: nil) { appearance in
            appearance.isDark
                ? NSColor(red: 0xA7/255, green: 0x8B/255, blue: 0xFA/255, alpha: 1)
                : NSColor(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255, alpha: 1)
        })
    }

    static var accent: Color {
        Color(nsColor: .init(name: nil) { appearance in
            appearance.isDark
                ? NSColor(red: 0x60/255, green: 0xA5/255, blue: 0xFA/255, alpha: 1)
                : NSColor(red: 0x25/255, green: 0x63/255, blue: 0xEB/255, alpha: 1)
        })
    }

    static var destructive: Color {
        Color(nsColor: .init(name: nil) { appearance in
            appearance.isDark
                ? NSColor(red: 0xF8/255, green: 0x71/255, blue: 0x71/255, alpha: 1)
                : NSColor(red: 0xDC/255, green: 0x26/255, blue: 0x26/255, alpha: 1)
        })
    }

    static var muted: Color {
        Color(nsColor: .init(name: nil) { appearance in
            appearance.isDark
                ? NSColor(red: 0x2A/255, green: 0x2A/255, blue: 0x2A/255, alpha: 1)
                : NSColor(red: 0xF0/255, green: 0xF0/255, blue: 0xF0/255, alpha: 1)
        })
    }

    static var mutedForeground: Color {
        Color(nsColor: .init(name: nil) { appearance in
            appearance.isDark
                ? NSColor(red: 0xA0/255, green: 0xA0/255, blue: 0xA0/255, alpha: 1)
                : NSColor(red: 0x73/255, green: 0x73/255, blue: 0x73/255, alpha: 1)
        })
    }

    static var border: Color {
        Color(nsColor: .init(name: nil) { appearance in
            appearance.isDark
                ? NSColor(red: 0x33/255, green: 0x33/255, blue: 0x33/255, alpha: 1)
                : NSColor(red: 0xE0/255, green: 0xE0/255, blue: 0xE0/255, alpha: 1)
        })
    }

    static var green: Color {
        Color(nsColor: .init(name: nil) { appearance in
            appearance.isDark
                ? NSColor(red: 0x4A/255, green: 0xDE/255, blue: 0x80/255, alpha: 1)
                : NSColor(red: 0x16/255, green: 0xA3/255, blue: 0x4A/255, alpha: 1)
        })
    }

    static var orange: Color {
        Color(nsColor: .init(name: nil) { appearance in
            appearance.isDark
                ? NSColor(red: 0xFB/255, green: 0x92/255, blue: 0x3C/255, alpha: 1)
                : NSColor(red: 0xEA/255, green: 0x58/255, blue: 0x0C/255, alpha: 1)
        })
    }

    static var shadow: Color {
        Color(nsColor: .init(name: nil) { appearance in
            appearance.isDark
                ? NSColor(white: 1, alpha: 0.06)
                : NSColor(red: 0x1A/255, green: 0x1A/255, blue: 0x1A/255, alpha: 0.12)
        })
    }

    static let borderWidth: CGFloat = 1.5
    static let shadowOffset: CGFloat = 3
    static let cornerRadius: CGFloat = 8
}

// MARK: - Appearance Helper

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .vibrantDark]) != nil
    }
}

// MARK: - Color Hex Init

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// MARK: - Neobrutalist Card

struct NeoBrutalistCard: ViewModifier {
    var filled: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(filled ? NeoTheme.card : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                    .stroke(NeoTheme.border, lineWidth: NeoTheme.borderWidth)
            )
            .shadow(
                color: colorScheme == .dark
                    ? Color.white.opacity(0.04)
                    : Color.black.opacity(0.1),
                radius: colorScheme == .dark ? 8 : 2,
                x: colorScheme == .dark ? 0 : NeoTheme.shadowOffset,
                y: colorScheme == .dark ? 0 : NeoTheme.shadowOffset
            )
    }
}

// MARK: - Neobrutalist Button

struct NeoBrutalistButton: ButtonStyle {
    var isPrimary: Bool = true
    var isDisabled: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(isPrimary ? Color.white : NeoTheme.foreground)
            .background(isPrimary ? NeoTheme.primary : NeoTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                    .stroke(
                        isPrimary ? Color.clear : NeoTheme.border,
                        lineWidth: NeoTheme.borderWidth
                    )
            )
            .shadow(
                color: colorScheme == .dark
                    ? Color.white.opacity(0.03)
                    : Color.black.opacity(0.1),
                radius: colorScheme == .dark ? 6 : 0,
                x: colorScheme == .dark ? 0 : (configuration.isPressed ? 0 : NeoTheme.shadowOffset),
                y: colorScheme == .dark ? 0 : (configuration.isPressed ? 0 : NeoTheme.shadowOffset)
            )
            .offset(
                x: configuration.isPressed ? NeoTheme.shadowOffset : 0,
                y: configuration.isPressed ? NeoTheme.shadowOffset : 0
            )
            .opacity(isDisabled ? 0.5 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Jelly Motion

extension Animation {
    static var neoJellySpring: Animation {
        .spring(duration: 0.58, bounce: 0.34)
    }
}

extension AnyTransition {
    static var neoJellyReveal: AnyTransition {
        .move(edge: .top)
            .combined(with: .scale(scale: 0.86, anchor: .top))
            .combined(with: .opacity)
    }
}

struct NeoJellyDisclosure<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let isExpanded: Bool
    let onToggle: () -> Void
    private let content: Content

    init(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color = NeoTheme.accent,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.neoJellySpring) {
                    onToggle()
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                            .fill(accent.opacity(0.14))
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                            .stroke(accent.opacity(0.45), lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(NeoTheme.foreground)
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(NeoTheme.mutedForeground)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(accent)
                        .frame(width: 28, height: 28)
                        .background(accent.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(accent.opacity(0.45), lineWidth: 1)
                        )
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .symbolEffect(.bounce, value: isExpanded)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NeoTheme.muted)
                .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius + 2))
                .overlay(
                    RoundedRectangle(cornerRadius: NeoTheme.cornerRadius + 2)
                        .stroke(NeoTheme.border, lineWidth: NeoTheme.borderWidth)
                )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .scaleEffect(isExpanded ? 0.985 : 1, anchor: .top)
            .animation(.neoJellySpring, value: isExpanded)

            if isExpanded {
                content
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NeoTheme.muted.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius + 2))
                    .overlay(
                        RoundedRectangle(cornerRadius: NeoTheme.cornerRadius + 2)
                            .stroke(NeoTheme.border, lineWidth: NeoTheme.borderWidth)
                    )
                    .transition(.neoJellyReveal)
            }
        }
        .animation(.neoJellySpring, value: isExpanded)
    }
}

// MARK: - Focus Style

extension View {
    func neoFocusDisabled() -> some View {
        self.focusEffectDisabled()
    }
}
