import Foundation

/// STUN/TURN ICE server configuration.
public struct ICEServerConfig: Codable, Sendable {
    public let url: String
    public let username: String?
    public let credential: String?

    public init(url: String, username: String? = nil, credential: String? = nil) {
        self.url = url
        self.username = username
        self.credential = credential
    }
}

/// ICE candidate gathering and NAT traversal state manager.
public final class NATTraversalEngine: @unchecked Sendable {
    public static let shared = NATTraversalEngine()

    public var iceServers: [ICEServerConfig] = [
        ICEServerConfig(url: "stun:stun.l.google.com:19302"),
        ICEServerConfig(url: "stun:stun1.l.google.com:19302")
    ]

    private var isRelayActive: Bool = false
    private let lock = NSLock()

    private init() {}

    /// Determine if direct P2P is achievable or if TURN relay fallback is required.
    public func evaluateConnectionPath(isDirectP2PSuccessful: Bool) -> TransportMode {
        lock.lock()
        defer { lock.unlock() }

        if isDirectP2PSuccessful {
            isRelayActive = false
            return .directP2P
        } else {
            isRelayActive = true
            return .relay
        }
    }

    /// Status indicating whether session is current using encrypted TURN relay fallback.
    public var isRelaying: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRelayActive
    }
}
