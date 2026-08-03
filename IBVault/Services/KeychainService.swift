import Foundation
import Security

enum KeychainError: Error, LocalizedError, Sendable {
    case encodingFailed
    case saveFailed(status: OSStatus)
    case loadFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case itemNotFound
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data for keychain"
        case .saveFailed(let status):
            return "Failed to save to keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load from keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from keychain (status: \(status))"
        case .itemNotFound:
            return "Item not found in keychain"
        }
    }
}

enum KeychainService {
    private static let service = "com.nootstudy.ibvault"
    private static let apiKeyAccount = "gemini_api_key"
    private static let junaliAPIKeyAccount = "junali_api_key"
    private static let userDefaultsFallbackKey = "gemini_api_key_fallback"

    static func saveAPIKey(_ key: String) -> Bool {
        saveSecret(key, account: apiKeyAccount)
    }

    static func loadAPIKey() -> String? {
        if let key = loadSecret(account: apiKeyAccount) {
            return key
        }

        // One-time migration from older builds that incorrectly persisted the
        // Gemini key in UserDefaults. Never retain the plaintext fallback.
        guard let legacy = UserDefaults.standard.string(forKey: userDefaultsFallbackKey), !legacy.isEmpty else {
            return nil
        }
        let migrated = saveSecret(legacy, account: apiKeyAccount)
        UserDefaults.standard.removeObject(forKey: userDefaultsFallbackKey)
        return migrated ? legacy : nil
    }

    static func deleteAPIKey() -> Bool {
        UserDefaults.standard.removeObject(forKey: userDefaultsFallbackKey)
        return deleteSecret(account: apiKeyAccount)
    }

    static var hasAPIKey: Bool {
        loadAPIKey()?.isEmpty == false
    }

    static func saveJunaliAPIKey(_ key: String) -> Bool {
        saveSecret(key, account: junaliAPIKeyAccount)
    }

    static func loadJunaliAPIKey() -> String? {
        loadSecret(account: junaliAPIKeyAccount)
    }

    static func deleteJunaliAPIKey() -> Bool {
        deleteSecret(account: junaliAPIKeyAccount)
    }

    static var hasJunaliAPIKey: Bool {
        loadJunaliAPIKey()?.isEmpty == false
    }

    private static func saveSecret(_ value: String, account: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }

        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var insertion = lookup
        insertion[kSecValueData as String] = data
        return SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess
    }

    private static func loadSecret(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func deleteSecret(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
