import Foundation

/// Model representing a trusted peer device and its default granted permissions.
public struct TrustedPeer: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var platform: DevicePlatform
    public var publicKeyData: Data
    public var defaultPermissions: RemoteSessionPermissions
    public var dateTrusted: Date
    public var lastConnected: Date?

    public init(
        id: String,
        name: String,
        platform: DevicePlatform,
        publicKeyData: Data,
        defaultPermissions: RemoteSessionPermissions = .standardDefault,
        dateTrusted: Date = Date(),
        lastConnected: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.publicKeyData = publicKeyData
        self.defaultPermissions = defaultPermissions
        self.dateTrusted = dateTrusted
        self.lastConnected = lastConnected
    }

    public static func == (lhs: TrustedPeer, rhs: TrustedPeer) -> Bool {
        return lhs.id == rhs.id
    }
}
