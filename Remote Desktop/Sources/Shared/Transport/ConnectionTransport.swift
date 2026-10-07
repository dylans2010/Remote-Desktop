import Foundation

/// Active network connection state of a remote session.
public enum TransportConnectionState: String, Codable, Sendable {
    case discovering
    case negotiating
    case connecting
    case directConnection
    case relayConnection
    case connected
    case reconnecting
    case disconnected
    case failed
}

/// Transport mode active for session.
public enum TransportMode: String, Codable, Sendable {
    case localLAN
    case directP2P
    case relay
}

/// Protocol defining the connection transport abstraction for local LAN, direct P2P, and TURN relay.
public protocol ConnectionTransportDelegate: AnyObject {
    func transport(_ transport: ConnectionTransport, didChangeState state: TransportConnectionState)
    func transport(_ transport: ConnectionTransport, didReceiveMessage message: ProtocolMessage)
    func transport(_ transport: ConnectionTransport, didReceiveMediaFrame frameData: Data, timestamp: Double)
    func transport(_ transport: ConnectionTransport, didFailWithError error: Error)
}

public protocol ConnectionTransport: AnyObject {
    var state: TransportConnectionState { get }
    var transportMode: TransportMode { get }
    var delegate: ConnectionTransportDelegate? { get set }

    func connect(to peer: Device) async throws
    func sendMessage(_ message: ProtocolMessage) async throws
    func sendMediaFrame(_ frameData: Data, timestamp: Double) async throws
    func disconnect()
}
