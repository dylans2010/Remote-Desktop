import Foundation
import CryptoKit
import Security

/// Cryptographic identity for a local or remote Remote Desktop device.
/// Uses Curve25519 asymmetric keys for secure device authentication and signatures.
public final class DeviceIdentity: Codable, @unchecked Sendable {
    public let deviceID: String
    public let deviceName: String
    public let platform: DevicePlatform
    public let publicKeyRepresentation: Data

    private let privateKey: Curve25519.Signing.PrivateKey

    public var capabilities: RemoteCapabilities {
        return platform == .macOS ? .macOSDefault : .iOSDefault
    }

    /// Initialize by generating a new identity or loading existing keys.
    public init(deviceName: String? = nil, platform: DevicePlatform? = nil, privateKey: Curve25519.Signing.PrivateKey? = nil) {
        let key = privateKey ?? Curve25519.Signing.PrivateKey()
        self.privateKey = key
        self.publicKeyRepresentation = key.publicKey.rawRepresentation

        // Derive a unique, deterministic Device ID from SHA256 of the public key
        let hashedKey = SHA256.hash(data: key.publicKey.rawRepresentation)
        self.deviceID = hashedKey.compactMap { String(format: "%02x", $0) }.joined()

        #if os(macOS)
        let defaultName = Host.current().localizedName ?? "Mac"
        let defaultPlatform = DevicePlatform.macOS
        #elseif os(iOS)
        let defaultName = "iPhone"
        let defaultPlatform = DevicePlatform.iOS
        #else
        let defaultName = "Apple Device"
        let defaultPlatform = DevicePlatform.unknown
        #endif
        self.deviceName = deviceName ?? defaultName
        self.platform = platform ?? defaultPlatform
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedCurrent: DeviceIdentity?

    /// Thread-safe access to persistent local device identity loaded from Keychain.
    public static var current: DeviceIdentity {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedCurrent {
            return cached
        }

        #if os(macOS)
        let name = Host.current().localizedName ?? "Mac"
        let plat = DevicePlatform.macOS
        #elseif os(iOS)
        let name = "iPhone"
        let plat = DevicePlatform.iOS
        #else
        let name = "Apple Device"
        let plat = DevicePlatform.unknown
        #endif

        if let savedKeyData = KeychainManager.shared.loadDevicePrivateKey(),
           let restored = try? DeviceIdentity.restore(from: savedKeyData, deviceName: name) {
            cachedCurrent = restored
            return restored
        }

        // Generate brand new identity and persist to Keychain
        let newIdentity = DeviceIdentity(deviceName: name, platform: plat)
        KeychainManager.shared.saveDevicePrivateKey(newIdentity.rawPrivateKeyData)
        cachedCurrent = newIdentity
        return newIdentity
    }

    /// Reset identity (used in unit tests)
    public static func resetCurrentIdentityForTesting() {
        lock.lock()
        defer { lock.unlock() }
        cachedCurrent = nil
        KeychainManager.shared.deleteDevicePrivateKey()
    }

    /// Export private key data for secure Keychain storage.
    public var rawPrivateKeyData: Data {
        return privateKey.rawRepresentation
    }

    /// Restore identity from raw private key data.
    public static func restore(from rawPrivateKeyData: Data, deviceName: String? = nil) throws -> DeviceIdentity {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawPrivateKeyData)
        return DeviceIdentity(deviceName: deviceName, privateKey: privateKey)
    }

    /// Sign challenge payload using the device's private key.
    public func sign(challenge: Data) throws -> Data {
        return try privateKey.signature(for: challenge)
    }

    /// Verify a signature from a remote peer's public key data.
    public static func verify(signature: Data, for challenge: Data, publicKeyData: Data) -> Bool {
        guard let peerPublicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            return false
        }
        return peerPublicKey.isValidSignature(signature, for: challenge)
    }

    // MARK: - Codable Conformance

    enum CodingKeys: String, CodingKey {
        case deviceID
        case deviceName
        case platform
        case publicKeyRepresentation
        case privateKeyData
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deviceID = try container.decode(String.self, forKey: .deviceID)
        self.deviceName = try container.decode(String.self, forKey: .deviceName)
        self.platform = try container.decodeIfPresent(DevicePlatform.self, forKey: .platform) ?? .macOS
        self.publicKeyRepresentation = try container.decode(Data.self, forKey: .publicKeyRepresentation)
        let privateData = try container.decode(Data.self, forKey: .privateKeyData)
        self.privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateData)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(platform, forKey: .platform)
        try container.encode(publicKeyRepresentation, forKey: .publicKeyRepresentation)
        try container.encode(privateKey.rawRepresentation, forKey: .privateKeyData)
    }
}
