import Foundation

/// Represents the platform operating system of a device.
public enum DevicePlatform: String, Codable, Sendable {
    case macOS
    case iOS
    case iPadOS
    case unknown
}

/// Represents the trust relationship state with a remote peer device.
public enum DeviceTrustStatus: String, Codable, Sendable {
    case trusted
    case pendingApproval
    case revoked
    case untrusted
}

/// Dynamic connection availability state.
public enum DeviceOnlineState: String, Codable, Sendable {
    case online
    case offline
    case connecting
    case busy
    case unavailable
    case needsPermission
}

/// Model representing a discovered, paired, or known remote device.
public struct Device: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var platform: DevicePlatform
    public var capabilities: RemoteCapabilities
    public var publicKeyData: Data
    public var trustStatus: DeviceTrustStatus
    public var onlineState: DeviceOnlineState
    public var lastSeen: Date
    public var isThisDevice: Bool
    public var ipAddress: String?
    public var port: UInt16?
    public var defaultPermissions: RemoteSessionPermissions

    public init(
        id: String,
        name: String,
        platform: DevicePlatform,
        publicKeyData: Data,
        capabilities: RemoteCapabilities? = nil,
        trustStatus: DeviceTrustStatus = .untrusted,
        onlineState: DeviceOnlineState = .offline,
        lastSeen: Date = Date(),
        isThisDevice: Bool = false,
        ipAddress: String? = nil,
        port: UInt16? = nil,
        defaultPermissions: RemoteSessionPermissions = .standardDefault
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.publicKeyData = publicKeyData
        self.capabilities = capabilities ?? (platform == .macOS ? .macOSDefault : .iOSDefault)
        self.trustStatus = trustStatus
        self.onlineState = onlineState
        self.lastSeen = lastSeen
        self.isThisDevice = isThisDevice
        self.ipAddress = ipAddress
        self.port = port
        self.defaultPermissions = defaultPermissions
    }

    public static func == (lhs: Device, rhs: Device) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Manages persistent trusted devices using Keychain storage.
public final class TrustModel: @unchecked Sendable {
    public static let shared = TrustModel()

    private var trustedDevicesMap: [String: Device] = [:]
    private let lock = NSLock()

    private init() {
        loadTrustedDevices()
    }

    /// Retrieve list of all known trusted devices.
    public var trustedDevices: [Device] {
        lock.lock()
        defer { lock.unlock() }
        return Array(trustedDevicesMap.values)
    }

    /// Check if a given device ID is trusted.
    public func isTrusted(deviceID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return trustedDevicesMap[deviceID]?.trustStatus == .trusted
    }

    /// Trust or update a device record.
    public func trustDevice(_ device: Device) {
        lock.lock()
        var updated = device
        updated.trustStatus = .trusted
        trustedDevicesMap[device.id] = updated
        let devicesArray = Array(trustedDevicesMap.values)
        lock.unlock()

        saveTrustedDevices(devicesArray)
    }

    /// Retrieve default permissions configured for a trusted device.
    public func defaultPermissions(for deviceID: String) -> RemoteSessionPermissions {
        lock.lock()
        defer { lock.unlock() }
        return trustedDevicesMap[deviceID]?.defaultPermissions ?? .standardDefault
    }

    /// Update default permissions for a trusted device.
    public func updateDefaultPermissions(for deviceID: String, permissions: RemoteSessionPermissions) {
        lock.lock()
        if var device = trustedDevicesMap[deviceID] {
            device.defaultPermissions = permissions
            trustedDevicesMap[deviceID] = device
        }
        let devicesArray = Array(trustedDevicesMap.values)
        lock.unlock()

        saveTrustedDevices(devicesArray)
    }

    /// Revoke trust for a device and terminate any active session with it.
    public func revokeDevice(deviceID: String) {
        lock.lock()
        if var device = trustedDevicesMap[deviceID] {
            device.trustStatus = .revoked
            trustedDevicesMap[deviceID] = device
        } else {
            trustedDevicesMap.removeValue(forKey: deviceID)
        }
        let devicesArray = Array(trustedDevicesMap.values)
        lock.unlock()

        saveTrustedDevices(devicesArray)

        // Terminate any active remote session with the revoked device immediately
        RemoteSessionManager.shared.handleTrustRevocation(deviceID: deviceID)
    }

    /// Remove a device completely.
    public func removeDevice(deviceID: String) {
        lock.lock()
        trustedDevicesMap.removeValue(forKey: deviceID)
        let devicesArray = Array(trustedDevicesMap.values)
        lock.unlock()

        saveTrustedDevices(devicesArray)
        RemoteSessionManager.shared.handleTrustRevocation(deviceID: deviceID)
    }

    // MARK: - Keychain Sync

    private func loadTrustedDevices() {
        guard let data = KeychainManager.shared.loadTrustedPeers(),
              let decoded = try? JSONDecoder().decode([Device].self, from: data) else {
            return
        }
        lock.lock()
        for device in decoded {
            trustedDevicesMap[device.id] = device
        }
        lock.unlock()
    }

    private func saveTrustedDevices(_ devices: [Device]) {
        guard let encoded = try? JSONEncoder().encode(devices) else { return }
        KeychainManager.shared.saveTrustedPeers(encoded)
    }
}
