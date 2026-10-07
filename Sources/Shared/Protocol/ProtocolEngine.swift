import Foundation

/// Protocol version identifier. Incompatible versions are rejected during negotiation.
public let CURRENT_PROTOCOL_VERSION: Int = 1

/// Strongly-typed network protocol message envelope and actions.
public enum ProtocolMessageType: String, Codable, Sendable {
    case hello
    case helloAck
    case authChallenge
    case authResponse
    case sessionNegotiation
    case sessionAccepted
    case pairRequest
    case pairAccepted
    case pairRejected
    case sessionOffer
    case sessionAnswer
    case iceCandidate
    case sessionRequest
    case sessionRejected
    case connectionRequest
    case connectionResponse
    case permissionUpdate
    case permissionRevoked
    case annotation
    case inputEvent
    case clipboardSync
    case fileOffer
    case fileAccept
    case fileChunk
    case fileComplete
    case fileCancel
    case ping
    case pong
    case disconnect
    case disconnectRequest
    case disconnectAck
    case sessionEnded
}

/// Strongly-typed payload for Remote Input events.
public struct RemoteInputEvent: Codable, Sendable {
    public enum InputType: String, Codable, Sendable {
        case mouseMove
        case mouseDown
        case mouseUp
        case rightMouseDown
        case rightMouseUp
        case scroll
        case keyDown
        case keyUp
        case drag
    }

    public let type: InputType
    public let x: Double?              // Normalized x (0.0 - 1.0)
    public let y: Double?              // Normalized y (0.0 - 1.0)
    public let deltaX: Double?         // Scroll delta X
    public let deltaY: Double?         // Scroll delta Y
    public let keyCode: UInt16?        // Key code
    public let modifiers: UInt32?      // CGEventFlags modifier flags bitmask
    public let text: String?           // Keyboard text insertion
    public let displayIndex: Int?      // Target display index

    public init(
        type: InputType,
        x: Double? = nil,
        y: Double? = nil,
        deltaX: Double? = nil,
        deltaY: Double? = nil,
        keyCode: UInt16? = nil,
        modifiers: UInt32? = nil,
        text: String? = nil,
        displayIndex: Int? = 0
    ) {
        self.type = type
        self.x = x
        self.y = y
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.text = text
        self.displayIndex = displayIndex
    }
}

/// Strongly-typed payload for Clipboard synchronization.
public struct ClipboardPayload: Codable, Sendable {
    public enum ClipboardType: String, Codable, Sendable {
        case text
        case image
    }

    public let type: ClipboardType
    public let textContent: String?
    public let dataContent: Data?

    public init(type: ClipboardType, textContent: String? = nil, dataContent: Data? = nil) {
        self.type = type
        self.textContent = textContent
        self.dataContent = dataContent
    }
}

/// Generic protocol message container exchanged across transports.
public struct ProtocolMessage: Codable, Sendable {
    public let version: Int
    public let type: ProtocolMessageType
    public let sessionID: SessionID?
    public let channel: TransportChannel?
    public let senderID: String
    public let targetID: String?
    public let payload: Data?
    public let timestamp: Date

    public init(
        type: ProtocolMessageType,
        senderID: String,
        targetID: String? = nil,
        sessionID: SessionID? = nil,
        channel: TransportChannel? = nil,
        payload: Data? = nil,
        version: Int = CURRENT_PROTOCOL_VERSION
    ) {
        self.version = version
        self.type = type
        self.senderID = senderID
        self.targetID = targetID
        self.sessionID = sessionID
        self.channel = channel
        self.payload = payload
        self.timestamp = Date()
    }
}

/// Encoder / Decoder engine for Protocol Messages.
public struct ProtocolEngine {
    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()

    public static func encode(_ message: ProtocolMessage) throws -> Data {
        return try jsonEncoder.encode(message)
    }

    public static func decode(_ data: Data) throws -> ProtocolMessage {
        let msg = try jsonDecoder.decode(ProtocolMessage.self, from: data)
        guard msg.version == CURRENT_PROTOCOL_VERSION else {
            throw NSError(domain: "RemoteDesktopProtocol", code: 101, userInfo: [
                NSLocalizedDescriptionKey: "Incompatible protocol version \(msg.version), expected \(CURRENT_PROTOCOL_VERSION)"
            ])
        }
        return msg
    }
}

// MARK: - Handshake Payloads (Requirement 8)

/// Payload for initial connection HELLO from Controller to Host.
public struct HelloPayload: Codable, Sendable {
    public let protocolVersion: Int
    public let clientID: String
    public let clientName: String
    public let clientPlatform: DevicePlatform
    public let sessionID: SessionID
    public let supportedCodecs: [String]

    public init(
        protocolVersion: Int = CURRENT_PROTOCOL_VERSION,
        clientID: String,
        clientName: String,
        clientPlatform: DevicePlatform,
        sessionID: SessionID,
        supportedCodecs: [String] = ["H.264"]
    ) {
        self.protocolVersion = protocolVersion
        self.clientID = clientID
        self.clientName = clientName
        self.clientPlatform = clientPlatform
        self.sessionID = sessionID
        self.supportedCodecs = supportedCodecs
    }
}

/// Payload response for HELLO_ACK from Host to Controller.
public struct HelloAckPayload: Codable, Sendable {
    public let protocolVersion: Int
    public let hostID: String
    public let hostName: String
    public let hostPlatform: DevicePlatform
    public let sessionID: SessionID
    public let supportedCodecs: [String]

    public init(
        protocolVersion: Int = CURRENT_PROTOCOL_VERSION,
        hostID: String,
        hostName: String,
        hostPlatform: DevicePlatform,
        sessionID: SessionID,
        supportedCodecs: [String] = ["H.264"]
    ) {
        self.protocolVersion = protocolVersion
        self.hostID = hostID
        self.hostName = hostName
        self.hostPlatform = hostPlatform
        self.sessionID = sessionID
        self.supportedCodecs = supportedCodecs
    }
}

/// Payload for AUTH_CHALLENGE from Controller to Host.
public struct AuthChallengePayload: Codable, Sendable {
    public let sessionID: SessionID
    public let requesterID: String
    public let challenge: Data
    public let requesterPublicKey: Data

    public init(sessionID: SessionID, requesterID: String, challenge: Data, requesterPublicKey: Data) {
        self.sessionID = sessionID
        self.requesterID = requesterID
        self.challenge = challenge
        self.requesterPublicKey = requesterPublicKey
    }
}

/// Payload for AUTH_RESPONSE from Host to Controller.
public struct AuthResponsePayload: Codable, Sendable {
    public let sessionID: SessionID
    public let signature: Data
    public let hostPublicKey: Data
    public let hostChallenge: Data?

    public init(sessionID: SessionID, signature: Data, hostPublicKey: Data, hostChallenge: Data? = nil) {
        self.sessionID = sessionID
        self.signature = signature
        self.hostPublicKey = hostPublicKey
        self.hostChallenge = hostChallenge
    }
}

/// Payload for SESSION_NEGOTIATION from Controller to Host.
public struct SessionNegotiationPayload: Codable, Sendable {
    public let sessionID: SessionID
    public let requestedPermissions: RemoteSessionPermissions
    public let capabilities: RemoteCapabilities
    public let preferredCodec: String
    public let targetWidth: Int
    public let targetHeight: Int
    public let frameRate: Int

    public init(
        sessionID: SessionID,
        requestedPermissions: RemoteSessionPermissions,
        capabilities: RemoteCapabilities,
        preferredCodec: String = "H.264",
        targetWidth: Int = 1920,
        targetHeight: Int = 1080,
        frameRate: Int = 60
    ) {
        self.sessionID = sessionID
        self.requestedPermissions = requestedPermissions
        self.capabilities = capabilities
        self.preferredCodec = preferredCodec
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
        self.frameRate = frameRate
    }
}

/// Payload for SESSION_ACCEPTED from Host to Controller.
public struct SessionAcceptedPayload: Codable, Sendable {
    public let sessionID: SessionID
    public let approved: Bool
    public let grantedPermissions: RemoteSessionPermissions
    public let negotiatedCodec: String
    public let negotiatedWidth: Int
    public let negotiatedHeight: Int
    public let negotiatedFrameRate: Int
    public let rejectionReason: String?

    public init(
        sessionID: SessionID,
        approved: Bool,
        grantedPermissions: RemoteSessionPermissions,
        negotiatedCodec: String = "H.264",
        negotiatedWidth: Int = 1920,
        negotiatedHeight: Int = 1080,
        negotiatedFrameRate: Int = 60,
        rejectionReason: String? = nil
    ) {
        self.sessionID = sessionID
        self.approved = approved
        self.grantedPermissions = grantedPermissions
        self.negotiatedCodec = negotiatedCodec
        self.negotiatedWidth = negotiatedWidth
        self.negotiatedHeight = negotiatedHeight
        self.negotiatedFrameRate = negotiatedFrameRate
        self.rejectionReason = rejectionReason
    }
}

// MARK: - Pairing Payloads

/// Payload sent by a device wishing to pair with a host using an entered pairing code.
public struct PairingRequestPayload: Codable, Sendable {
    public let candidateCode: String
    public let requesterID: String
    public let requesterName: String
    public let requesterPlatform: DevicePlatform
    public let requesterPublicKey: Data
    public let requesterChallenge: Data
    public let requesterCapabilities: RemoteCapabilities

    public init(
        candidateCode: String,
        requesterID: String,
        requesterName: String,
        requesterPlatform: DevicePlatform,
        requesterPublicKey: Data,
        requesterChallenge: Data,
        requesterCapabilities: RemoteCapabilities
    ) {
        self.candidateCode = candidateCode
        self.requesterID = requesterID
        self.requesterName = requesterName
        self.requesterPlatform = requesterPlatform
        self.requesterPublicKey = requesterPublicKey
        self.requesterChallenge = requesterChallenge
        self.requesterCapabilities = requesterCapabilities
    }
}

/// Payload response from host for a pairing request.
public struct PairingResponsePayload: Codable, Sendable {
    public let accepted: Bool
    public let rejectionReason: String?
    public let hostID: String?
    public let hostName: String?
    public let hostPlatform: DevicePlatform?
    public let hostPublicKey: Data?
    public let hostSignature: Data?
    public let hostChallenge: Data?
    public let hostCapabilities: RemoteCapabilities?

    public init(
        accepted: Bool,
        rejectionReason: String? = nil,
        hostID: String? = nil,
        hostName: String? = nil,
        hostPlatform: DevicePlatform? = nil,
        hostPublicKey: Data? = nil,
        hostSignature: Data? = nil,
        hostChallenge: Data? = nil,
        hostCapabilities: RemoteCapabilities? = nil
    ) {
        self.accepted = accepted
        self.rejectionReason = rejectionReason
        self.hostID = hostID
        self.hostName = hostName
        self.hostPlatform = hostPlatform
        self.hostPublicKey = hostPublicKey
        self.hostSignature = hostSignature
        self.hostChallenge = hostChallenge
        self.hostCapabilities = hostCapabilities
    }
}

/// Payload sent by requester to finalize mutual authentication.
public struct PairingConfirmPayload: Codable, Sendable {
    public let requesterID: String
    public let requesterSignature: Data

    public init(requesterID: String, requesterSignature: Data) {
        self.requesterID = requesterID
        self.requesterSignature = requesterSignature
    }
}

// MARK: - Negotiation & Handshake Payloads (Legacy)

/// Payload for incoming session connection requests from a controller to a host.
public struct ConnectionRequestPayload: Codable, Sendable {
    public let requesterID: String
    public let requesterName: String
    public let requesterPlatform: DevicePlatform
    public let requestedPermissions: RemoteSessionPermissions
    public let capabilities: RemoteCapabilities
    public let challenge: Data?

    public init(
        requesterID: String,
        requesterName: String,
        requesterPlatform: DevicePlatform,
        requestedPermissions: RemoteSessionPermissions,
        capabilities: RemoteCapabilities,
        challenge: Data? = nil
    ) {
        self.requesterID = requesterID
        self.requesterName = requesterName
        self.requesterPlatform = requesterPlatform
        self.requestedPermissions = requestedPermissions
        self.capabilities = capabilities
        self.challenge = challenge
    }
}

/// Payload response from host accepting or rejecting a connection request.
public struct ConnectionResponsePayload: Codable, Sendable {
    public let approved: Bool
    public let hostID: String
    public let hostName: String
    public let grantedPermissions: RemoteSessionPermissions
    public let hostCapabilities: RemoteCapabilities
    public let rejectionReason: String?
    public let hostSignature: Data?
    public let hostChallenge: Data?

    public init(
        approved: Bool,
        hostID: String,
        hostName: String,
        grantedPermissions: RemoteSessionPermissions,
        hostCapabilities: RemoteCapabilities,
        rejectionReason: String? = nil,
        hostSignature: Data? = nil,
        hostChallenge: Data? = nil
    ) {
        self.approved = approved
        self.hostID = hostID
        self.hostName = hostName
        self.grantedPermissions = grantedPermissions
        self.hostCapabilities = hostCapabilities
        self.rejectionReason = rejectionReason
        self.hostSignature = hostSignature
        self.hostChallenge = hostChallenge
    }
}

/// Payload sent by host to dynamically update permissions during an active session.
public struct PermissionUpdatePayload: Codable, Sendable {
    public let updatedPermissions: RemoteSessionPermissions
    public let reason: String?

    public init(updatedPermissions: RemoteSessionPermissions, reason: String? = nil) {
        self.updatedPermissions = updatedPermissions
        self.reason = reason
    }
}

/// Payload for orderly disconnect requests.
public struct DisconnectPayload: Codable, Sendable {
    public let reason: String
    public let requestedBy: String

    public init(reason: String = "User requested disconnect", requestedBy: String) {
        self.reason = reason
        self.requestedBy = requestedBy
    }
}

/// Payload notifying that a session has ended.
public struct SessionEndedPayload: Codable, Sendable {
    public let reason: String
    public let endedByHost: Bool

    public init(reason: String, endedByHost: Bool) {
        self.reason = reason
        self.endedByHost = endedByHost
    }
}
