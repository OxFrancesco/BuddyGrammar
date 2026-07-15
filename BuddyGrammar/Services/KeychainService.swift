import Foundation
import Security

final class KeychainService {
    static let openRouterService = "BuddyGrammar.OpenRouter"
    static let openRouterAccount = "openrouter_api_key"
    static let elevenLabsService = "BuddyGrammar.ElevenLabs"
    static let elevenLabsAccount = "elevenlabs_api_key"

    private var cachedAPIKey: String?
    private var hasLoadedAPIKey = false
    private var cachedElevenLabsAPIKey: String?
    private var hasLoadedElevenLabsAPIKey = false

    func saveAPIKey(_ apiKey: String) throws {
        try save(apiKey, service: Self.openRouterService, account: Self.openRouterAccount)
        cachedAPIKey = apiKey
        hasLoadedAPIKey = true
    }

    func loadAPIKey() -> String? {
        if hasLoadedAPIKey {
            return cachedAPIKey
        }

        let value = load(service: Self.openRouterService, account: Self.openRouterAccount)
        cachedAPIKey = value
        hasLoadedAPIKey = true
        return value
    }

    func deleteAPIKey() {
        delete(service: Self.openRouterService, account: Self.openRouterAccount)
        cachedAPIKey = nil
        hasLoadedAPIKey = true
    }

    func hasAPIKey() -> Bool {
        loadAPIKey()?.isEmpty == false
    }

    func saveElevenLabsAPIKey(_ apiKey: String) throws {
        try save(apiKey, service: Self.elevenLabsService, account: Self.elevenLabsAccount)
        cachedElevenLabsAPIKey = apiKey
        hasLoadedElevenLabsAPIKey = true
    }

    func loadElevenLabsAPIKey() -> String? {
        if hasLoadedElevenLabsAPIKey {
            return cachedElevenLabsAPIKey
        }

        let value = load(service: Self.elevenLabsService, account: Self.elevenLabsAccount)
        cachedElevenLabsAPIKey = value
        hasLoadedElevenLabsAPIKey = true
        return value
    }

    func deleteElevenLabsAPIKey() {
        delete(service: Self.elevenLabsService, account: Self.elevenLabsAccount)
        cachedElevenLabsAPIKey = nil
        hasLoadedElevenLabsAPIKey = true
    }

    func hasElevenLabsAPIKey() -> Bool {
        loadElevenLabsAPIKey()?.isEmpty == false
    }

    private func save(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        let query = query(service: service, account: account)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    private func load(service: String, account: String) -> String? {
        var query = query(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    private func delete(service: String, account: String) {
        SecItemDelete(query(service: service, account: account) as CFDictionary)
    }

    private func query(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum KeychainError: Error {
    case unhandled(OSStatus)
}
