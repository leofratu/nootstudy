import Foundation
import Security

/// Manages the local integration bridge bearer token.
/// - 32 random bytes via SecRandomCopyBytes, stored in Keychain (service "com.nootstudy.ibvault.bridge", account "bridge-token")
/// - In-memory cache, constant-time comparison, regenerateToken(), enabled flag in UserDefaults.
/// Never log or return the token except through explicit user-facing copy APIs.
nonisolated enum BridgeAuthService: Sendable {
    private static let service = "com.nootstudy.ibvault.bridge"
    private static let account = "bridge-token"
    private static let enabledKey = "BridgeEnabled"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedToken: String?

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Returns the current token, generating and persisting one if absent.
    static func token() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedToken, !cached.isEmpty {
            return cached
        }
        if let stored = loadFromKeychain(), !stored.isEmpty {
            cachedToken = stored
            return stored
        }
        let generated = generateToken()
        // Persist; ignore failure but cache anyway so caller gets a token
        _ = saveToKeychain(generated)
        cachedToken = generated
        return generated
    }

    /// Generates a new token, persists it, and updates the cache.
    @discardableResult
    static func regenerateToken() -> String {
        lock.lock()
        defer { lock.unlock() }
        let newToken = generateToken()
        _ = saveToKeychain(newToken)
        cachedToken = newToken
        return newToken
    }

    /// For testing: clear in-memory cache (does not delete keychain).
    static func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedToken = nil
    }

    /// Constant-time comparison to mitigate timing side-channels.
    static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        guard lhsBytes.count == rhsBytes.count else {
            // Still compare to avoid early exit leaking length? But length already leaked.
            // Do dummy comparison to keep timing similar.
            var dummy: UInt8 = 0
            let maxCount = max(lhsBytes.count, rhsBytes.count)
            for i in 0..<maxCount {
                let a = i < lhsBytes.count ? lhsBytes[i] : 0
                let b = i < rhsBytes.count ? rhsBytes[i] : 0
                dummy |= a ^ b
            }
            _ = dummy
            return false
        }
        var result: UInt8 = 0
        for (a, b) in zip(lhsBytes, rhsBytes) {
            result |= a ^ b
        }
        return result == 0
    }

    /// Validates a bearer header value against the stored token.
    static func isValidBearer(_ headerValue: String?) -> Bool {
        guard let headerValue else { return false }
        let prefix = "Bearer "
        guard headerValue.hasPrefix(prefix) else { return false }
        let presented = String(headerValue.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = token()
        return constantTimeEqual(presented, expected)
    }

    // MARK: - Private

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // Fallback to arc4random if SecRandom fails (should never happen)
            for i in 0..<bytes.count {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }
        // Base64URL without padding for URL-safe bearer token
        let data = Data(bytes)
        var base64 = data.base64EncodedString()
        base64 = base64.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return base64
    }

    private static func saveToKeychain(_ token: String) -> Bool {
        // Test hosts must never touch the real Keychain; the token remains in
        // the in-memory cache for the lifetime of the test process.
        if AppEnvironment.isRunningTests { return true }
        guard let data = token.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }
        var insertion = query
        insertion[kSecValueData as String] = data
        return SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess
    }

    private static func loadFromKeychain() -> String? {
        if AppEnvironment.isRunningTests { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }
}
