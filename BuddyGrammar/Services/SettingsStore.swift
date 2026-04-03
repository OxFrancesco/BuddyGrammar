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
        let storedProfiles: [PromptProfile]? = Self.loadValue(for: Keys.profiles, from: defaults, decoder: decoder)
        self.profiles = Self.normalizeProfiles(storedProfiles)
        persist(self.profiles, key: Keys.profiles)
    }

    func markOnboardingComplete() {
        appSettings.hasCompletedOnboarding = true
    }

    func update(_ profile: PromptProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        if updated.isStandard {
            updated.name = PromptProfile.standard.name
            updated.instruction = PromptProfile.standard.instruction
            updated.isBuiltIn = true
        }
        if updated.hotkey == nil {
            updated.isEnabled = false
        }
        var nextProfiles = profiles
        nextProfiles[index] = updated
        profiles = Self.normalizeProfiles(nextProfiles)
    }

    func addProfile(template: PersonalityTemplate = .blankCustom) -> UUID {
        let profile = template.makeProfile(availableHotkeys: availableHotkeys())
        profiles = Self.normalizeProfiles(profiles + [profile])
        return profile.id
    }

    func removeProfile(id: UUID) {
        guard let profile = profile(id: id), !profile.isBuiltIn else { return }
        profiles = Self.normalizeProfiles(profiles.filter { $0.id != id })
    }

    func moveProfile(id: UUID, direction: MoveDirection) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        guard !profiles[index].isStandard else { return }

        let minimumIndex = hasStandardPersonality ? 1 : 0
        let newIndex = switch direction {
        case .up: max(index - 1, minimumIndex)
        case .down: min(index + 1, profiles.count - 1)
        }
        guard newIndex != index else { return }
        var nextProfiles = profiles
        let profile = nextProfiles.remove(at: index)
        nextProfiles.insert(profile, at: newIndex)
        profiles = Self.normalizeProfiles(nextProfiles)
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

    var hasStandardPersonality: Bool {
        profiles.contains { $0.isStandard }
    }

    private func availableHotkeys() -> Set<HotkeyDescriptor> {
        let takenHotkeys = Set(profiles.compactMap(\.hotkey))
        return Set(PersonalityTemplate.allCases.compactMap(\.suggestedHotkey)).subtracting(takenHotkeys)
    }

    private static func normalizeProfiles(_ storedProfiles: [PromptProfile]?) -> [PromptProfile] {
        guard let storedProfiles else {
            return [PromptProfile.standard]
        }

        var normalized = storedProfiles

        if let index = normalized.firstIndex(where: { $0.id == PromptProfile.grammarProfileID }) {
            let existing = normalized[index]
            if existing.matchesLegacyBuiltInDefinition() || existing.usesLockedStandardContent {
                var standard = PromptProfile.standard
                standard.hotkey = existing.hotkey
                standard.isEnabled = existing.hotkey != nil ? existing.isEnabled : false
                normalized[index] = standard
            } else {
                var preservedCustom = existing
                preservedCustom.id = UUID()
                preservedCustom.isBuiltIn = false

                var standard = PromptProfile.standard
                standard.hotkey = nil
                standard.isEnabled = false

                normalized[index] = standard
                normalized.insert(preservedCustom, at: index + 1)
            }
        } else {
            var standard = PromptProfile.standard
            standard.hotkey = nil
            standard.isEnabled = false
            normalized.insert(standard, at: 0)
        }

        for index in normalized.indices {
            if normalized[index].id == PromptProfile.grammarProfileID {
                normalized[index].name = PromptProfile.standard.name
                normalized[index].instruction = PromptProfile.standard.instruction
                normalized[index].isBuiltIn = true
            } else {
                normalized[index].isBuiltIn = false
            }

            if normalized[index].hotkey == nil {
                normalized[index].isEnabled = false
            }
        }

        if let standardIndex = normalized.firstIndex(where: { $0.id == PromptProfile.grammarProfileID }), standardIndex != 0 {
            let standard = normalized.remove(at: standardIndex)
            normalized.insert(standard, at: 0)
        }

        return normalized
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
