import Foundation

/// Authoritative session state machine representing every stage of a remote desktop connection.
public enum SessionState: String, Codable, Sendable, Equatable {
    case idle
    case pairing
    case requestingPermission
    case awaitingApproval
    case negotiating
    case connecting
    case establishingMedia
    case connected
    case reconnecting
    case disconnecting
    case disconnected

    // Failure states
    case permissionDenied
    case authenticationFailed
    case mediaFailed
    case connectionTimeout
    case peerDisconnected
    case captureUnavailable
    case transportFailed

    /// Indicates whether the session is currently in an active, connected, or connecting state.
    public var isActive: Bool {
        switch self {
        case .requestingPermission, .awaitingApproval, .negotiating, .connecting, .establishingMedia, .connected, .reconnecting:
            return true
        default:
            return false
        }
    }

    /// Indicates whether remote control / media rendering is currently live.
    public var isLiveMediaActive: Bool {
        return self == .connected
    }

    /// Indicates whether this is a terminal or error state requiring user intervention.
    public var isTerminal: Bool {
        switch self {
        case .idle, .disconnected, .permissionDenied, .authenticationFailed, .mediaFailed, .connectionTimeout, .peerDisconnected, .captureUnavailable, .transportFailed:
            return true
        default:
            return false
        }
    }

    /// User-friendly status description for UI rendering.
    public var statusDescription: String {
        switch self {
        case .idle:
            return "Ready"
        case .pairing:
            return "Pairing Device..."
        case .requestingPermission:
            return "Requesting Connection..."
        case .awaitingApproval:
            return "Awaiting Host Approval..."
        case .negotiating:
            return "Negotiating Session..."
        case .connecting:
            return "Connecting..."
        case .establishingMedia:
            return "Starting Screen Stream..."
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting..."
        case .disconnecting:
            return "Disconnecting..."
        case .disconnected:
            return "Disconnected"
        case .permissionDenied:
            return "Connection Declined by Host"
        case .authenticationFailed:
            return "Authentication Failed"
        case .mediaFailed:
            return "Screen Stream Failed"
        case .connectionTimeout:
            return "Connection Timed Out"
        case .peerDisconnected:
            return "Remote Device Disconnected"
        case .captureUnavailable:
            return "Screen Recording Not Authorized"
        case .transportFailed:
            return "Network Connection Failed"
        }
    }
}
