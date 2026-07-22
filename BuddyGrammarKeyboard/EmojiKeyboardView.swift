import BuddyGrammarKit
import SwiftUI

@MainActor
struct RecentEmojiStore {
    private let defaults: UserDefaults
    private let key = "keyboard.recentEmoji"
    private let capacity = 24

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    func record(_ emoji: String) -> [String] {
        var recents = load()
        recents.removeAll { $0 == emoji }
        recents.insert(emoji, at: 0)
        if recents.count > capacity {
            recents.removeLast(recents.count - capacity)
        }
        defaults.set(recents, forKey: key)
        return recents
    }
}

struct EmojiKeyboardLayer: View {
    private static let catalog = (try? EmojiCatalog.bundled()) ?? .empty

    let model: KeyboardModel
    let metrics: KeyboardMetrics

    @State private var selectedCategoryID = EmojiKeyboardLayer.catalog.categories.first?.id ?? ""
    @State private var recents: [String] = []
    @State private var searchText = ""
    @State private var searchResults: [EmojiEntry] = []
    @State private var isSearchEditing = false

    private let store = RecentEmojiStore()

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedEntries: [EmojiEntry] {
        if selectedCategoryID == "recents" {
            return recents.compactMap { Self.catalog.entry(for: $0) }
        }
        return Self.catalog.categories
            .first(where: { $0.id == selectedCategoryID })?
            .entries ?? []
    }

    private var visibleEntries: [EmojiEntry] {
        isSearching ? searchResults : selectedEntries
    }

    var body: some View {
        VStack(spacing: 5) {
            EmojiSearchBar(
                text: $searchText,
                isEditing: $isSearchEditing,
                playInputClick: model.playInputClick
            )

            if !isSearchEditing {
                EmojiCategoryTabs(
                    categories: Self.catalog.categories,
                    showsRecents: !recents.isEmpty,
                    selectedCategoryID: $selectedCategoryID,
                    playInputClick: model.playInputClick
                )
            }

            EmojiGrid(
                entries: visibleEntries,
                searchText: isSearching ? searchText : nil,
                onSelect: insertEmoji
            )
            .frame(maxHeight: .infinity)

            if isSearchEditing {
                EmojiSearchKeyboard(
                    text: $searchText,
                    dismiss: { isSearchEditing = false },
                    playInputClick: model.playInputClick
                )
            }

            keyboardControls
        }
        .onAppear(perform: restoreRecents)
        .onChange(of: searchText) { _, newValue in
            searchResults = Self.catalog.search(newValue, limit: 180)
        }
    }

    private var keyboardControls: some View {
        HStack(spacing: metrics.keySpacing) {
            Button("ABC") {
                model.playInputClick()
                model.setLayout(.letters)
            }
            .font(.callout)
            .buttonStyle(
                KeyboardFunctionButtonStyle(
                    width: metrics.wideFunctionKeyWidth * 1.2,
                    height: 38
                )
            )
            .accessibilityLabel("Show letters")
            .accessibilityIdentifier("keyboard.layout")

            Button {
                model.playInputClick()
                model.insertSpace()
            } label: {
                Text("space")
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(KeyboardKeyButtonStyle())
            .accessibilityIdentifier("keyboard.space")

            Button {
                model.playInputClick()
                model.deleteBackward()
            } label: {
                Image(systemName: "delete.left")
                    .frame(width: metrics.wideFunctionKeyWidth, height: 38)
            }
            .buttonStyle(
                KeyboardFunctionButtonStyle(
                    width: metrics.wideFunctionKeyWidth,
                    height: 38
                )
            )
            .accessibilityLabel("Delete")
            .accessibilityIdentifier("keyboard.delete")
        }
    }

    private func restoreRecents() {
        recents = store.load().filter { Self.catalog.entry(for: $0) != nil }
        if !recents.isEmpty {
            selectedCategoryID = "recents"
        }
    }

    private func insertEmoji(_ sequence: String) {
        model.playInputClick()
        model.insertEmoji(sequence)
        recents = store.record(sequence)
    }
}

private struct EmojiSearchBar: View {
    @Binding var text: String
    @Binding var isEditing: Bool
    let playInputClick: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Button {
                playInputClick()
                isEditing = true
            } label: {
                Text(text.isEmpty ? "Search emoji" : text)
                    .font(.callout)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text.isEmpty ? "Search emoji" : "Emoji search: \(text)")
            .accessibilityHint("Shows the emoji search keyboard")

            Button {
                playInputClick()
                text = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear emoji search")
            .opacity(text.isEmpty ? 0 : 1)
            .disabled(text.isEmpty)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(Color(uiColor: .systemGray6), in: .rect(cornerRadius: 8))
        .accessibilityIdentifier("keyboard.emojiSearch")
    }
}

/// A custom keyboard extension cannot rely on another software keyboard to
/// edit a search field. This small local surface edits only the in-memory
/// query and never inserts search text into the host document.
private struct EmojiSearchKeyboard: View {
    private static let rows = [
        Array("qwertyuiop"),
        Array("asdfghjkl"),
        Array("zxcvbnm"),
    ]

    @Binding var text: String
    let dismiss: () -> Void
    let playInputClick: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { character in
                        Button {
                            playInputClick()
                            text.append(character)
                        } label: {
                            Text(String(character))
                                .frame(maxWidth: .infinity, minHeight: 24)
                        }
                        .font(.caption.weight(.medium))
                        .buttonStyle(KeyboardKeyButtonStyle())
                        .accessibilityLabel(String(character))
                        .accessibilityHint("Adds to emoji search")
                    }
                }
                .padding(
                    .horizontal,
                    row == Self.rows[1] ? 10 : row == Self.rows[2] ? 22 : 0
                )
            }

            HStack(spacing: 4) {
                Button {
                    if !text.isEmpty {
                        playInputClick()
                        text.removeLast()
                    }
                } label: {
                    Image(systemName: "delete.left")
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                .buttonStyle(KeyboardKeyButtonStyle())
                .accessibilityLabel("Delete search character")
                .disabled(text.isEmpty)

                Button {
                    guard !text.isEmpty, text.last != " " else { return }
                    playInputClick()
                    text.append(" ")
                } label: {
                    Text("space")
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                .font(.caption)
                .buttonStyle(KeyboardKeyButtonStyle())
                .accessibilityLabel("Search space")

                Button {
                    playInputClick()
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(KeyboardKeyButtonStyle())
                    .accessibilityHint("Hides the emoji search keyboard")
            }
        }
        .sensoryFeedback(.selection, trigger: text)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Emoji search keyboard")
    }
}

private struct EmojiCategoryTabs: View {
    let categories: [EmojiCategory]
    let showsRecents: Bool
    @Binding var selectedCategoryID: String
    let playInputClick: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if showsRecents {
                    EmojiCategoryTab(
                        id: "recents",
                        name: "Recents",
                        icon: "clock",
                        isSelected: selectedCategoryID == "recents",
                        select: select,
                        playInputClick: playInputClick
                    )
                }
                ForEach(categories) { category in
                    EmojiCategoryTab(
                        id: category.id,
                        name: category.name,
                        icon: category.icon,
                        isSelected: selectedCategoryID == category.id,
                        select: select,
                        playInputClick: playInputClick
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Emoji categories")
    }

    private func select(_ id: String) {
        selectedCategoryID = id
    }
}

private struct EmojiCategoryTab: View {
    let id: String
    let name: String
    let icon: String
    let isSelected: Bool
    let select: (String) -> Void
    let playInputClick: () -> Void

    var body: some View {
        Button {
            playInputClick()
            select(id)
        } label: {
            Image(systemName: icon)
                .font(.footnote)
                .frame(width: 36, height: 28)
                .background(
                    isSelected ? Color(uiColor: .systemGray3) : Color.clear,
                    in: .rect(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("keyboard.emojiCategory.\(id)")
    }
}

private struct EmojiGrid: View {
    private static let columns = [
        GridItem(.adaptive(minimum: 38, maximum: 48), spacing: 4),
    ]

    let entries: [EmojiEntry]
    let searchText: String?
    let onSelect: (String) -> Void

    var body: some View {
        if entries.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(searchText == nil ? "No emoji available" : "No emoji found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 6) {
                    ForEach(entries) { entry in
                        EmojiKey(entry: entry, onSelect: onSelect)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

private struct EmojiKey: View {
    let entry: EmojiEntry
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            onSelect(entry.sequence)
        } label: {
            Text(entry.sequence)
                .font(.title2)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.name)
        .accessibilityHint(
            entry.variants.isEmpty
                ? "Inserts this emoji"
                : "Inserts this emoji. Touch and hold to choose a skin tone"
        )
        .contextMenu {
            ForEach(entry.variants) { variant in
                Button {
                    onSelect(variant.sequence)
                } label: {
                    Text(variant.sequence)
                    Text(variant.skinTones.joined(separator: ", "))
                }
                .accessibilityLabel(variant.name)
            }
        }
    }
}
