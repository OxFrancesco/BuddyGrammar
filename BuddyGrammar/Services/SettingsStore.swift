import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private enum Keys {
        static let settings = "BuddyGrammar.settings"
        static let profiles = "BuddyGrammar.profiles"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var appSettings: AppSettings {
        didSet {
            persist(appSettings, key: Keys.settings)
            onSettingsChanged?(appSettings)
        }
    }

    var profiles: [PromptProfile] {
        didSet {
            persist(profiles, key: Keys.profiles)
            onProfilesChanged?(profiles)
        }
    }

    var onProfilesChanged: (([PromptProfile]) -> Void)?
    var onSettingsChanged: ((AppSettings) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appSettings = Self.loadValue(for: Keys.settings, from: defaults, decoder: decoder) ?? .default
        self.profiles = Self.loadValue(for: Keys.profiles, from: defaults, decoder: decoder) ?? [PromptProfile.grammar]
        ensureBuiltInProfile()
    }

    func markOnboardingComplete() {
        appSettings.hasCompletedOnboarding = true
    }

    func update(_ profile: PromptProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
    }

    func addProfile() -> UUID {
        let profile = PromptProfile.newCustomProfile()
        profiles.append(profile)
        return profile.id
    }

    func removeProfile(id: UUID) {
        guard let profile = profile(id: id), !profile.isBuiltIn else { return }
        profiles.removeAll { $0.id == id }
    }

    func moveProfile(id: UUID, direction: MoveDirection) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = switch direction {
        case .up: max(index - 1, 0)
        case .down: min(index + 1, profiles.count - 1)
        }
        guard newIndex != index else { return }
        let profile = profiles.remove(at: index)
        profiles.insert(profile, at: newIndex)
    }

    func profile(id: UUID) -> PromptProfile? {
        profiles.first { $0.id == id }
    }

    func hotkeyConflict(for profileID: UUID, hotkey: HotkeyDescriptor?) -> PromptProfile? {
        guard let hotkey else { return nil }
        return profiles.first { other in
            other.id != profileID &&
            other.isEnabled &&
            other.hotkey == hotkey
        }
    }

    func enabledProfilesWithHotkeys() -> [PromptProfile] {
        profiles.filter { $0.isEnabled && $0.hotkey?.isValid == true }
    }

    static func hasDuplicateHotkeys(in profiles: [PromptProfile]) -> Bool {
        var seen = Set<HotkeyDescriptor>()
        for profile in profiles where profile.isEnabled {
            guard let hotkey = profile.hotkey else { continue }
            if !seen.insert(hotkey).inserted {
                return true
            }
        }
        return false
    }

    private func ensureBuiltInProfile() {
        guard let index = profiles.firstIndex(where: { $0.id == PromptProfile.grammarProfileID }) else {
            profiles.insert(.grammar, at: 0)
            return
        }

        var grammarProfile = profiles[index]
        var didChange = false

        if !grammarProfile.isBuiltIn {
            grammarProfile.isBuiltIn = true
            didChange = true
        }

        if grammarProfile.hotkey == PromptProfile.legacyGrammarHotkey {
            grammarProfile.hotkey = PromptProfile.defaultGrammarHotkey
            didChange = true
        }

        if didChange {
            profiles[index] = grammarProfile
        }
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadValue<T: Decodable>(
        for key: String,
        from defaults: UserDefaults,
        decoder: JSONDecoder
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}

enum MoveDirection {
    case up
    case down
}
