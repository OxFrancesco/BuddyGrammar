import Foundation

public enum SuggestionEmojiMap {
    public static let keywordToEmoji: [String: String] = [
        "100": "💯", "fire": "🔥", "love": "❤️", "heart": "❤️", "lol": "😂",
        "haha": "😂", "laugh": "😂", "ok": "👌", "okay": "👌", "star": "⭐",
        "party": "🎉", "sad": "😢", "cool": "😎", "money": "💰", "pizza": "🍕",
        "coffee": "☕", "sun": "☀️", "rain": "🌧️", "cat": "🐱", "dog": "🐶",
        "thanks": "🙏", "thank": "🙏", "yes": "✅", "no": "❌", "idea": "💡",
        "rocket": "🚀", "happy": "😊", "angry": "😠", "cry": "😭", "kiss": "😘",
        "wink": "😉", "beer": "🍺", "wine": "🍷", "music": "🎵", "gift": "🎁",
        "birthday": "🎂", "snow": "❄️", "moon": "🌙", "tree": "🌳", "flower": "🌸",
        "book": "📚", "phone": "📱", "car": "🚗", "plane": "✈️", "home": "🏠",
        "house": "🏠", "work": "💼", "clock": "⏰", "eyes": "👀", "strong": "💪",
        "muscle": "💪", "clap": "👏", "wave": "👋", "think": "🤔", "sleep": "😴",
        "goat": "🐐", "win": "🏆", "trophy": "🏆", "soccer": "⚽", "basketball": "🏀",
        "run": "🏃", "beach": "🏖️", "hug": "🤗", "sparkles": "✨", "boom": "💥",
        "skull": "💀", "ghost": "👻", "king": "👑", "diamond": "💎", "key": "🔑",
        "warning": "⚠️", "new": "🆕", "top": "🔝", "soon": "🔜",
    ]

    public static func emoji(for word: String) -> String? {
        keywordToEmoji[word.lowercased()]
    }
}
