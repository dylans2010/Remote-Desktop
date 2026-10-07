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
