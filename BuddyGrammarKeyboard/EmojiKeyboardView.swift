import SwiftUI

struct EmojiCategory: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let emoji: [String]
}

enum EmojiCatalog {
    static let categories: [EmojiCategory] = [
        EmojiCategory(
            id: "smileys",
            name: "Smileys",
            icon: "face.smiling",
            emoji: "😀😃😄😁😆😅😂🤣🙂🙃😉😊😇🥰😍🤩😘😗😚😙😋😛😜🤪😝🤑🤗🤭🤫🤔🤐🤨😐😑😶😏😒🙄😬🤥😌😔😪🤤😴😷🤒🤕🤢🤮🥵🥶😵🤯🤠🥳😎🤓🧐😕😟🙁😮😯😲😳🥺😦😨😰😥😢😭😱😖😞😓😩😫🥱😤😡😠🤬".map(String.init)
        ),
        EmojiCategory(
            id: "people",
            name: "People",
            icon: "hand.wave",
            emoji: "👋🤚🖐️✋🖖👌🤌🤏✌️🤞🤟🤘🤙👈👉👆👇☝️👍👎✊👊🤛🤜👏🙌👐🤲🤝🙏💪🦾🦵🦶👂👃🧠🦷👀👅👄👶🧒👦👧🧑👱👨🧔👩🧓👴👵🙍🙎🙅🙆💁🙋🧏🙇🤦🤷".map(String.init)
        ),
        EmojiCategory(
            id: "animals",
            name: "Animals",
            icon: "pawprint",
            emoji: "🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🙈🙉🙊🐒🐔🐧🐦🐤🐣🦆🦅🦉🦇🐺🐗🐴🦄🐝🐛🦋🐌🐞🐜🕷️🦂🐢🐍🦎🦖🦕🐙🦑🦐🦞🦀🐡🐠🐟🐬🐳🐋🦈🐊🐅🐆🦓🦍🐘🦒🐪🐄🐎🐖🐏🐑🐐".map(String.init)
        ),
        EmojiCategory(
            id: "food",
            name: "Food",
            icon: "fork.knife",
            emoji: "🍏🍎🍐🍊🍋🍌🍉🍇🍓🫐🍈🍒🍑🥭🍍🥥🥝🍅🍆🥑🥦🥬🥒🌶️🌽🥕🧄🧅🥔🍠🥐🍞🥖🥨🧀🥚🍳🥞🧇🥓🥩🍗🍖🌭🍔🍟🍕🥪🌮🌯🥗🍝🍜🍲🍛🍣🍱🥟🍤🍙🍚🍧🍨🍦🥧🧁🍰🎂🍮🍭🍬🍫🍿🍩🍪☕🍵🧃🥤🍶🍺🍻🥂🍷🍸🍹".map(String.init)
        ),
        EmojiCategory(
            id: "activities",
            name: "Activities",
            icon: "figure.run",
            emoji: "⚽🏀🏈⚾🥎🎾🏐🏉🥏🎱🏓🏸🏒🏑🥍🏏🥅⛳🏹🎣🤿🥊🥋🎽🛹🛼🛷⛸️🥌🎿⛷️🏂🏋️🤼🤸⛹️🤺🤾🏌️🏇🧘🏄🏊🤽🚣🧗🚵🚴🏆🥇🥈🥉🏅🎖️🎫🎟️🎪🤹🎭🩰🎨🎬🎤🎧🎼🎹🥁🎷🎺🎸🪕🎻🎲🎯🎳🎮🎰🧩".map(String.init)
        ),
        EmojiCategory(
            id: "travel",
            name: "Travel",
            icon: "car",
            emoji: "🚗🚕🚙🚌🚎🏎️🚓🚑🚒🚐🛻🚚🚛🚜🛴🚲🛵🏍️🚨🚔🚖🚡🚠🚃🚋🚄🚅🚈🚂🚆🚇🚊🚉✈️🛫🛬🛩️💺🛰️🚀🛸🚁🛶⛵🚤🛥️🛳️⛴️🚢⚓⛽🚧🚦🚥🗺️🗿🗽🗼🏰🏯🏟️🎡🎢🎠⛲🏖️🏝️🏜️🌋⛰️🏔️🗻🏕️⛺🏠🏡🏘️🏗️🏭🏢🏬🏥🏦🏨🏪🏫💒🏛️⛪🕌🕍🛕⛩️".map(String.init)
        ),
        EmojiCategory(
            id: "objects",
            name: "Objects",
            icon: "lightbulb",
            emoji: "⌚📱📲💻⌨️🖥️🖨️🖱️🕹️💽💾💿📀📼📷📸📹🎥📽️🎞️📞☎️📟📠📺📻🎙️🧭⏱️⏲️⏰⌛⏳📡🔋🔌💡🔦🕯️🧯💸💵💴💶💷💰💳💎⚖️🧰🔧🔨⚒️🛠️⛏️🔩⚙️🧱⛓️🧲💣🧨🔪🗡️⚔️🛡️🔮📿🧿💈🔭🔬💊💉🩸🧬🦠🧫🧪🌡️🧹🧺🧻🚽🚿🛁🧼🧽🛎️🔑🗝️🚪🪑🛋️🛏️🧸🖼️🛍️🛒🎁🎈🎏🎀🎊🎉".map(String.init)
        ),
        EmojiCategory(
            id: "symbols",
            name: "Symbols",
            icon: "heart",
            emoji: "❤️🧡💛💚💙💜🖤🤍🤎💔❣️💕💞💓💗💖💘💝💟☮️✝️☪️🕉️☸️✡️🔯🕎☯️☦️⛎♈♉♊♋♌♍♎♏♐♑♒♓🆔⚛️✅❌❓❗💯🔞📴📳🈶🈚🈸🈺🈷️✴️🆚💮🉐㊙️㊗️🈴🈵🈹🈲🅰️🅱️🆎🆑🅾️🆘⛔📛🚫💢♨️🚷🚯🚳🚱🚭".map(String.init)
        ),
    ]
}

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
    let model: KeyboardModel
    let metrics: KeyboardMetrics

    @State private var selectedCategoryID = EmojiCatalog.categories[0].id
    @State private var recents: [String] = []

    private let store = RecentEmojiStore()

    private var selectedCategory: EmojiCategory {
        EmojiCatalog.categories.first { $0.id == selectedCategoryID } ?? EmojiCatalog.categories[0]
    }

    var body: some View {
        VStack(spacing: 6) {
            categoryTabs

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 38, maximum: 48), spacing: 4)],
                    spacing: 6
                ) {
                    if selectedCategoryID == "recents" {
                        emojiButtons(recents)
                    } else {
                        emojiButtons(selectedCategory.emoji)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: metrics.keySpacing) {
                Button("ABC") {
                    model.setLayout(.letters)
                }
                .font(.callout)
                .buttonStyle(
                    KeyboardFunctionButtonStyle(width: metrics.wideFunctionKeyWidth * 1.2, height: 38)
                )
                .accessibilityLabel("Show letters")
                .accessibilityIdentifier("keyboard.layout")

                Button(action: model.insertSpace) {
                    Text("space")
                        .font(.callout)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(KeyboardKeyButtonStyle())
                .accessibilityIdentifier("keyboard.space")

                Button(action: model.deleteBackward) {
                    Image(systemName: "delete.left")
                        .frame(width: metrics.wideFunctionKeyWidth, height: 38)
                }
                .buttonStyle(
                    KeyboardFunctionButtonStyle(width: metrics.wideFunctionKeyWidth, height: 38)
                )
                .accessibilityLabel("Delete")
                .accessibilityIdentifier("keyboard.delete")
            }
        }
        .onAppear {
            recents = store.load()
            if !recents.isEmpty {
                selectedCategoryID = "recents"
            }
        }
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if !recents.isEmpty {
                    categoryTab(id: "recents", name: "Recents", icon: "clock")
                }
                ForEach(EmojiCatalog.categories) { category in
                    categoryTab(id: category.id, name: category.name, icon: category.icon)
                }
            }
        }
    }

    private func categoryTab(id: String, name: String, icon: String) -> some View {
        Button {
            selectedCategoryID = id
        } label: {
            Image(systemName: icon)
                .font(.footnote)
                .frame(width: 36, height: 28)
                .background(
                    selectedCategoryID == id
                        ? Color(uiColor: .systemGray3)
                        : Color.clear
                )
                .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityIdentifier("keyboard.emojiCategory.\(id)")
    }

    @ViewBuilder
    private func emojiButtons(_ emoji: [String]) -> some View {
        ForEach(emoji, id: \.self) { symbol in
            Button {
                model.insertEmoji(symbol)
                recents = store.record(symbol)
            } label: {
                Text(symbol)
                    .font(.title2)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(symbol)
        }
    }
}
