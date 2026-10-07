import Foundation

/// Protocol version identifier. Incompatible versions are rejected during negotiation.
public let CURRENT_PROTOCOL_VERSION: Int = 1

/// Strongly-typed network protocol message envelope and actions.
public enum ProtocolMessageType: String, Codable, Sendable {
    case hello
    case pairRequest
    case pairAccepted
    case pairRejected
    case sessionOffer
    case sessionAnswer
    case iceCandidate
    case sessionRequest
    case sessionAccepted
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
    public let senderID: String
    public let targetID: String?
    public let payload: Data?
    public let timestamp: Date

    public init(
        type: ProtocolMessageType,
        senderID: String,
        targetID: String? = nil,
        payload: Data? = nil,
        version: Int = CURRENT_PROTOCOL_VERSION
    ) {
        self.version = version
        self.type = type
        self.senderID = senderID
        self.targetID = targetID
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

// MARK: - Negotiation & Handshake Payloads

/// Payload for incoming session connection requests from a controller to a host.
public struct ConnectionRequestPayload: Codable, Sendable {
    public let requesterID: String
    public let requesterName: String
    public let requesterPlatform: DevicePlatform
    public let requestedPermissions: RemoteSessionPermissions
    public let capabilities: RemoteCapabilities

    public init(
        requesterID: String,
        requesterName: String,
        requesterPlatform: DevicePlatform,
        requestedPermissions: RemoteSessionPermissions,
        capabilities: RemoteCapabilities
    ) {
        self.requesterID = requesterID
        self.requesterName = requesterName
        self.requesterPlatform = requesterPlatform
        self.requestedPermissions = requestedPermissions
        self.capabilities = capabilities
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

    public init(
        approved: Bool,
        hostID: String,
        hostName: String,
        grantedPermissions: RemoteSessionPermissions,
        hostCapabilities: RemoteCapabilities,
        rejectionReason: String? = nil
    ) {
        self.approved = approved
        self.hostID = hostID
        self.hostName = hostName
        self.grantedPermissions = grantedPermissions
        self.hostCapabilities = hostCapabilities
        self.rejectionReason = rejectionReason
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

