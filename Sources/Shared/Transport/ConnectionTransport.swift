import Foundation

/// Real transport state machine representing every stage of the network and session lifecycle.
public enum TransportState: @unchecked Sendable, Equatable, Codable {
    case idle
    case connecting
    case authenticating
    case negotiating
    case ready
    case reconnecting
    case disconnecting
    case disconnected
    case failed(Error)

    public static func == (lhs: TransportState, rhs: TransportState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.connecting, .connecting),
             (.authenticating, .authenticating),
             (.negotiating, .negotiating),
             (.ready, .ready),
             (.reconnecting, .reconnecting),
             (.disconnecting, .disconnecting),
             (.disconnected, .disconnected):
            return true
        case (.failed(let e1), .failed(let e2)):
            return e1.localizedDescription == e2.localizedDescription
        default:
            return false
        }
    }

    public var isReady: Bool {
        return self == .ready
    }

    public var description: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting"
        case .authenticating: return "Authenticating"
        case .negotiating: return "Negotiating"
        case .ready: return "Ready"
        case .reconnecting: return "Reconnecting"
        case .disconnecting: return "Disconnecting"
        case .disconnected: return "Disconnected"
        case .failed(let err): return "Failed (\(err.localizedDescription))"
        }
    }

    // Codable conformance
    enum CodingKeys: CodingKey {
        case rawValue
        case errorDescription
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle: try container.encode("idle", forKey: .rawValue)
        case .connecting: try container.encode("connecting", forKey: .rawValue)
        case .authenticating: try container.encode("authenticating", forKey: .rawValue)
        case .negotiating: try container.encode("negotiating", forKey: .rawValue)
        case .ready: try container.encode("ready", forKey: .rawValue)
        case .reconnecting: try container.encode("reconnecting", forKey: .rawValue)
        case .disconnecting: try container.encode("disconnecting", forKey: .rawValue)
        case .disconnected: try container.encode("disconnected", forKey: .rawValue)
        case .failed(let error):
            try container.encode("failed", forKey: .rawValue)
            try container.encode(error.localizedDescription, forKey: .errorDescription)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .rawValue)
        switch raw {
        case "idle": self = .idle
        case "connecting": self = .connecting
        case "authenticating": self = .authenticating
        case "negotiating": self = .negotiating
        case "ready": self = .ready
        case "reconnecting": self = .reconnecting
        case "disconnecting": self = .disconnecting
        case "disconnected": self = .disconnected
        case "failed":
            let desc = (try? container.decode(String.self, forKey: .errorDescription)) ?? "Transport failure"
            self = .failed(NSError(domain: "RemoteTransport", code: -1, userInfo: [NSLocalizedDescriptionKey: desc]))
        default:
            self = .idle
        }
    }
}

/// Backwards compatibility alias for existing references.
public typealias TransportConnectionState = TransportState

/// Unique identifier assigned to every remote desktop connection session.
public struct SessionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String {
        return rawValue.uuidString
    }
}

/// Logical channel identifiers multiplexed across transport.
public enum TransportChannel: UInt8, Codable, Sendable {
    case control = 0x01
    case authentication = 0x02
    case session = 0x03
    case mediaVideo = 0x04
    case mediaAudio = 0x05
    case input = 0x06
    case annotation = 0x07
    case clipboard = 0x08
    case fileTransfer = 0x09
}

/// Transport mode active for session.
public enum TransportMode: String, Codable, Sendable {
    case localLAN
    case directP2P
    case relay
}

/// Live transport telemetry diagnostics.
public struct TransportDiagnostics: Codable, Sendable {
    public var state: TransportState
    public var connectionStartedAt: Date?
    public var connectedAt: Date?
    public var authenticatedAt: Date?
    public var readyAt: Date?

    public var bytesSent: UInt64
    public var bytesReceived: UInt64

    public var messagesSent: UInt64
    public var messagesReceived: UInt64

    public var lastSend: Date?
    public var lastReceive: Date?

    public var reconnectCount: UInt
    public var lastError: String?
    public var activeCandidate: ConnectionCandidate?

    public init(
        state: TransportState = .idle,
        connectionStartedAt: Date? = nil,
        connectedAt: Date? = nil,
        authenticatedAt: Date? = nil,
        readyAt: Date? = nil,
        bytesSent: UInt64 = 0,
        bytesReceived: UInt64 = 0,
        messagesSent: UInt64 = 0,
        messagesReceived: UInt64 = 0,
        lastSend: Date? = nil,
        lastReceive: Date? = nil,
        reconnectCount: UInt = 0,
        lastError: String? = nil,
        activeCandidate: ConnectionCandidate? = nil
    ) {
        self.state = state
        self.connectionStartedAt = connectionStartedAt
        self.connectedAt = connectedAt
        self.authenticatedAt = authenticatedAt
        self.readyAt = readyAt
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
        self.messagesSent = messagesSent
        self.messagesReceived = messagesReceived
        self.lastSend = lastSend
        self.lastReceive = lastReceive
        self.reconnectCount = reconnectCount
        self.lastError = lastError
        self.activeCandidate = activeCandidate
    }
}

/// Developer Connection Diagnostics snapshot (Requirement 13).
public struct ConnectionDiagnosticsSnapshot: Codable, Sendable {
    public let peerName: String
    public let deviceIdentityStatus: String
    public let pairingStatus: String
    public let endpoint: String
    public let endpointSource: String
    public let reachability: String
    public let transportState: String
    public let handshakeState: String
    public let authState: String
    public let sessionState: String
    public let localPath: String

    public init(
        peerName: String = "Unknown",
        deviceIdentityStatus: String = "VALID",
        pairingStatus: String = "VALID",
        endpoint: String = "Unknown",
        endpointSource: String = "Unknown",
        reachability: String = "UNKNOWN",
        transportState: String = "IDLE",
        handshakeState: String = "NOT STARTED",
        authState: String = "NOT STARTED",
        sessionState: String = "NOT STARTED",
        localPath: String = ""
    ) {
        self.peerName = peerName
        self.deviceIdentityStatus = deviceIdentityStatus
        self.pairingStatus = pairingStatus
        self.endpoint = endpoint
        self.endpointSource = endpointSource
        self.reachability = reachability
        self.transportState = transportState
        self.handshakeState = handshakeState
        self.authState = authState
        self.sessionState = sessionState
        self.localPath = localPath
    }
}

/// Strongly-typed transport error diagnostics replacing generic "Transport not connected".
public enum TransportError: LocalizedError, Sendable {
    case notReady(state: TransportState, sessionID: SessionID?, peerName: String?)
    case connectionFailed(peer: String, endpoint: String, underlying: Error)
    case allCandidatesFailed(peer: String, attempts: [(candidate: String, reason: String)])
    case connectionTimeout(peer: String, stage: String)
    case handshakeFailed(stage: String, reason: String, tcpOk: Bool, authOk: Bool, sessionOk: Bool)
    case invalidSession(expected: SessionID?, received: SessionID?)
    case unauthenticatedPeer(peerID: String)
    case sessionTerminated(reason: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notReady(let state, let sessionID, let peerName):
            let sID = sessionID?.description.prefix(8) ?? "None"
            let pName = peerName ?? "Unknown"
            return "Unable to establish transport\nState: \(state.description)\nPeer: \(pName)\nSession: \(sID)\nError: Transport is not ready"
        case .connectionFailed(let peer, let endpoint, let underlying):
            return "Unable to establish transport\nPeer: \(peer)\nEndpoint: \(endpoint)\nError: \(underlying.localizedDescription)"
        case .allCandidatesFailed(let peer, let attempts):
            let details = attempts.map { "  • \($0.candidate): \($0.reason)" }.joined(separator: "\n")
            return "Unable to reach \(peer). All connection candidates failed:\n\(details)"
        case .connectionTimeout(let peer, let stage):
            return "Transport connection timed out\nPeer: \(peer)\nStage: \(stage)"
        case .handshakeFailed(let stage, let reason, let tcpOk, let authOk, let sessionOk):
            return """
            Transport handshake failed
            Stage: \(stage)
            Reason: \(reason)
            TCP connection: \(tcpOk ? "OK" : "FAILED")
            Authentication: \(authOk ? "OK" : "FAILED")
            Session negotiation: \(sessionOk ? "OK" : "NOT STARTED")
            Media: NOT STARTED
            """
        case .invalidSession(let expected, let received):
            let exp = expected?.description.prefix(8) ?? "None"
            let rec = received?.description.prefix(8) ?? "None"
            return "Session ID mismatch: expected \(exp), received \(rec)"
        case .unauthenticatedPeer(let peerID):
            return "Peer \(peerID) is not authenticated"
        case .sessionTerminated(let reason):
            return "Session terminated: \(reason)"
        case .cancelled:
            return "Transport connection cancelled"
        }
    }
}

/// Abstract interface for a remote transport connection.
public protocol RemoteTransport: AnyObject {
    var state: TransportState { get }
    var diagnostics: TransportDiagnostics { get }

    func connect(to peer: Device) async throws
    func disconnect()
    func waitUntilReady() async throws
    func send(_ message: Data) async throws
    func receive() async throws -> Data
}

/// Protocol defining the connection transport abstraction for local LAN, direct P2P, and TURN relay.
public protocol ConnectionTransportDelegate: AnyObject {
    func transport(_ transport: ConnectionTransport, didChangeState state: TransportState)
    func transport(_ transport: ConnectionTransport, didReceiveMessage message: ProtocolMessage)
    func transport(_ transport: ConnectionTransport, didReceiveMediaFrame frameData: Data, timestamp: Double)
    func transport(_ transport: ConnectionTransport, didFailWithError error: Error)
}

public protocol ConnectionTransport: AnyObject, Sendable {
    var state: TransportState { get }
    var transportMode: TransportMode { get }
    var sessionID: SessionID? { get set }
    var diagnostics: TransportDiagnostics { get }
    var delegate: ConnectionTransportDelegate? { get set }

    func connect(to peer: Device) async throws
    func waitUntilReady() async throws
    func sendMessage(_ message: ProtocolMessage) async throws
    func sendMediaFrame(_ frameData: Data, timestamp: Double) async throws
    func markReady()
    func disconnect()
}
