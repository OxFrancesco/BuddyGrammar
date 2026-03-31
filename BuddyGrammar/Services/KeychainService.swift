import Foundation
import Security

final class KeychainService {
    private let service = "BuddyGrammar.OpenRouter"
    private let account = "openrouter_api_key"
    private var cachedAPIKey: String?
    private var hasLoadedAPIKey = false

    func saveAPIKey(_ apiKey: String) throws {
        guard let data = apiKey.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }

        cachedAPIKey = apiKey
        hasLoadedAPIKey = true
    }

    func loadAPIKey() -> String? {
        if hasLoadedAPIKey {
            return cachedAPIKey
        }

        let value = loadAPIKeyFromKeychain()
        cachedAPIKey = value
        hasLoadedAPIKey = true
        return value
    }

    private func loadAPIKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return string
    }

    func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        cachedAPIKey = nil
        hasLoadedAPIKey = true
    }

    func hasAPIKey() -> Bool {
        loadAPIKey()?.isEmpty == false
    }
}

enum KeychainError: Error {
    case unhandled(OSStatus)
}
