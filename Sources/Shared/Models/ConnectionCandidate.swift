import Foundation
import Network

/// Classification of transport connection channels.
public enum TransportKind: String, Codable, Sendable {
    case lanIPv4 = "LAN IPv4"
    case lanIPv6 = "LAN IPv6"
    case bonjourService = "Local Peer Discovery"
    case directInternet = "Direct Internet"
    case relay = "Relay"
}

/// Source that provided the candidate endpoint.
public enum EndpointSource: String, Codable, Sendable {
    case bonjour = "Bonjour"
    case localInterface = "Local Interface"
    case manual = "Manual"
    case signaling = "Signaling"
    case cached = "Cached"
}

/// Concrete network endpoint candidate for connecting to a peer device.
public struct ConnectionCandidate: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: String { "\(transport.rawValue)_\(host):\(port)_\(interface ?? "")" }
    public let transport: TransportKind
    public let host: String
    public let port: UInt16
    public let priority: Int
    public let expiresAt: Date
    public let source: EndpointSource
    public let interface: String?
    public let isIPv6: Bool
    public var isReachable: Bool?

    public init(
        transport: TransportKind,
        host: String,
        port: UInt16 = 58900,
        priority: Int = 10,
        expiresAt: Date = Date().addingTimeInterval(300),
        source: EndpointSource = .bonjour,
        interface: String? = nil,
        isIPv6: Bool = false,
        isReachable: Bool? = nil
    ) {
        self.transport = transport
        self.host = host
        self.port = port
        self.priority = priority
        self.expiresAt = expiresAt
        self.source = source
        self.interface = interface
        self.isIPv6 = isIPv6
        self.isReachable = isReachable
    }

    public var isExpired: Bool {
        return Date() > expiresAt
    }

    public var formattedString: String {
        return "\(host):\(port)"
    }

    public var isLoopbackOrLocalhost: Bool {
        let lower = host.lowercased()
        return lower == "localhost" || lower == "127.0.0.1" || lower == "::1" || lower.hasPrefix("127.")
    }

    /// Formatted log description complying with Requirement 2.
    public var logDescription: String {
        let formatter = ISO8601DateFormatter()
        return """
          transport: \(transport.rawValue)
          host: \(host)
          port: \(port)
          IPv4/IPv6: \(isIPv6 ? "IPv6" : "IPv4")
          interface: \(interface ?? "default")
          source: \(source.rawValue)
          expiration: \(formatter.string(from: expiresAt))
        """
    }

    /// Convert to NWEndpoint for Network.framework connection establishment.
    public func toNWEndpoint() -> NWEndpoint {
        if transport == .bonjourService {
            return NWEndpoint.service(
                name: host,
                type: "_remotedesktop._tcp",
                domain: "local.",
                interface: nil
            )
        } else {
            let nwPort = NWEndpoint.Port(rawValue: port) ?? 58900
            return NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        }
    }
}

extension ConnectionCandidate: Comparable {
    public static func < (lhs: ConnectionCandidate, rhs: ConnectionCandidate) -> Bool {
        return lhs.priority > rhs.priority // higher priority comes first
    }
}
