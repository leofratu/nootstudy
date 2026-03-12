import Foundation
import Security

struct KeychainService {
    private static let userDefaultsKey = "gemini_api_key"

    static func saveAPIKey(_ key: String) -> Bool {
        UserDefaults.standard.set(key, forKey: userDefaultsKey)
        return true
    }

    static func loadAPIKey() -> String? {
        return UserDefaults.standard.string(forKey: userDefaultsKey)
    }

    static func deleteAPIKey() -> Bool {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        return true
    }

    static var hasAPIKey: Bool {
        loadAPIKey() != nil
    }
}
