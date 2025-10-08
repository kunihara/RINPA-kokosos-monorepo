import Foundation
import Security

enum InstallGuard {
    private static let keychainService = "com.kokosos.install"
    private static let keychainAccount = "install_sentinel"
    private static let defaultsKey = "InstallSentinel"

    /// Returns true when Keychain still has a previous sentinel but UserDefaults is empty,
    /// which indicates this is a fresh app install on a device with leftover Keychain data.
    static func isReinstall() -> Bool {
        let kc = readKeychain()
        let ud = UserDefaults.standard.string(forKey: defaultsKey)
        return kc != nil && ud == nil
    }

    /// Ensure both Keychain and UserDefaults have a matching sentinel.
    /// Call this after handling reinstall logic.
    static func ensureSentinel() {
        var sentinel = UserDefaults.standard.string(forKey: defaultsKey)
        if sentinel == nil { sentinel = readKeychain() }
        if sentinel == nil { sentinel = UUID().uuidString }
        if let s = sentinel {
            UserDefaults.standard.set(s, forKey: defaultsKey)
            writeKeychain(value: s)
        }
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data, let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    private static func writeKeychain(value: String) {
        // Delete any existing
        let delQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(delQuery as CFDictionary)
        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: value.data(using: .utf8) as Any
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}

