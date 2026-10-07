import Foundation
import Security

/// Secure storage abstraction wrapping Apple's Keychain APIs.
/// Stores private keys, peer certificates, trusted devices, and authentication tokens safely.
public final class KeychainManager: Sendable {
    public static let shared = KeychainManager()

    private let serviceIdentifier = "com.dylans2010.RemoteDesktop.keychain"
    private let identityKey = "com.dylans2010.RemoteDesktop.devicePrivateKey"
    private let trustedPeersKey = "com.dylans2010.RemoteDesktop.trustedPeers"

    private init() {}

    /// Save local device private key.
    @discardableResult
    public func saveDevicePrivateKey(_ keyData: Data) -> Bool {
        return saveData(keyData, forKey: identityKey)
    }

    /// Load local device private key.
    public func loadDevicePrivateKey() -> Data? {
        return loadData(forKey: identityKey)
    }

    /// Delete local device identity from Keychain.
    @discardableResult
    public func deleteDevicePrivateKey() -> Bool {
        return deleteData(forKey: identityKey)
    }

    /// Save trusted peer device information list encoded as Data.
    @discardableResult
    public func saveTrustedPeers(_ data: Data) -> Bool {
        return saveData(data, forKey: trustedPeersKey)
    }

    /// Load trusted peer list Data.
    public func loadTrustedPeers() -> Data? {
        return loadData(forKey: trustedPeersKey)
    }

    // MARK: - Internal Keychain CRUD

    private func saveData(_ data: Data, forKey key: String) -> Bool {
        deleteData(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func loadData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return data
        }
        return nil
    }

    private func deleteData(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
