import Foundation
import Network

/// Concrete connection transport implementation using Network.framework NWConnection / NWListener for direct LAN & TCP peer connection.
public final class LocalNetworkTransport: ConnectionTransport, @unchecked Sendable {
    public private(set) var state: TransportConnectionState = .disconnected
    public private(set) var transportMode: TransportMode = .localLAN
    public weak var delegate: ConnectionTransportDelegate?

    private var connection: NWConnection?
    private var listener: NWListener?
    private let lock = NSLock()

    private func withStateLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }

    public init() {}

    public func connect(to peer: Device) async throws {
        withStateLock {
            state = .connecting
            delegate?.transport(self, didChangeState: state)
        }

        guard let host = peer.ipAddress else {
            withStateLock {
                state = .failed
                delegate?.transport(self, didChangeState: state)
            }
            throw NSError(domain: "LocalNetworkTransport", code: 400, userInfo: [NSLocalizedDescriptionKey: "Peer IP address missing"])
        }

        let port = NWEndpoint.Port(rawValue: peer.port ?? 58900) ?? 58900
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)
        let nwConn = NWConnection(to: endpoint, using: .tcp)

        withStateLock {
            self.connection = nwConn
        }

        nwConn.stateUpdateHandler = { [weak self] connState in
            guard let self = self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }

            switch connState {
            case .ready:
                self.state = .connected
                self.delegate?.transport(self, didChangeState: .connected)
                self.receiveNextMessage()
            case .failed(let err):
                self.state = .failed
                self.delegate?.transport(self, didFailWithError: err)
            case .cancelled:
                self.state = .disconnected
                self.delegate?.transport(self, didChangeState: .disconnected)
            default:
                break
            }
        }

        nwConn.start(queue: .global(qos: .userInitiated))
    }

    public func sendMessage(_ message: ProtocolMessage) async throws {
        let data = try ProtocolEngine.encode(message)
        let conn = withStateLock { connection }

        guard let conn = conn, state == .connected else {
            throw NSError(domain: "LocalNetworkTransport", code: 500, userInfo: [NSLocalizedDescriptionKey: "Transport not connected"])
        }

        var length = UInt32(data.count).bigEndian
        var payload = Data(bytes: &length, count: 4)
        payload.append(data)

        conn.send(content: payload, completion: .contentProcessed({ error in
            if let error = error {
                print("[LocalNetworkTransport] Send error: \(error)")
            }
        }))
    }

    public func sendMediaFrame(_ frameData: Data, timestamp: Double) async throws {
        let frameMsg = ProtocolMessage(type: .sessionOffer, senderID: "media", payload: frameData)
        try await sendMessage(frameMsg)
    }

    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }

        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        state = .disconnected
        delegate?.transport(self, didChangeState: .disconnected)
    }

    private func receiveNextMessage() {
        lock.lock()
        let conn = connection
        lock.unlock()

        conn?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, isComplete, error in
            guard let self = self, let lengthData = content, lengthData.count == 4 else { return }

            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            conn?.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { payloadData, _, _, _ in
                if let data = payloadData, let msg = try? ProtocolEngine.decode(data) {
                    self.delegate?.transport(self, didReceiveMessage: msg)
                }
                self.receiveNextMessage()
            }
        }
    }
}
