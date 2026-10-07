import Foundation
import Network

/// Concrete connection transport implementation using Network.framework NWConnection
/// Supporting both client outgoing connections and server-accepted incoming peer connections.
public final class LocalNetworkTransport: ConnectionTransport, @unchecked Sendable {
    public private(set) var state: TransportConnectionState = .disconnected
    public private(set) var transportMode: TransportMode = .localLAN
    public weak var delegate: ConnectionTransportDelegate?

    private var connection: NWConnection?
    private let lock = NSLock()
    private var receivedBuffer = Data()
    private var isReceiving = false

    // Packet type tags
    private static let tagProtocolMessage: UInt8 = 0x01
    private static let tagMediaFrame: UInt8 = 0x02

    private func withStateLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }

    /// Client initializer for connecting out to a peer.
    public init() {}

    /// Server initializer for wrapping an incoming accepted NWConnection.
    public init(acceptedConnection: NWConnection) {
        self.connection = acceptedConnection
        setupConnection(acceptedConnection)
    }

    /// Connect out to a remote peer device over TCP.
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

        setupConnection(nwConn)
    }

    /// Configures state handler and starts receiving from connection.
    private func setupConnection(_ nwConn: NWConnection) {
        nwConn.stateUpdateHandler = { [weak self] connState in
            guard let self = self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }

            switch connState {
            case .ready:
                self.state = .connected
                self.delegate?.transport(self, didChangeState: .connected)
                self.startReceivingLoop()
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

        nwConn.start(queue: .global(qos: .userInteractive))
    }

    // MARK: - Message Transmission

    /// Send a structured protocol message (encoded with 0x01 tag).
    public func sendMessage(_ message: ProtocolMessage) async throws {
        let msgData = try ProtocolEngine.encode(message)
        let conn = withStateLock { connection }

        guard let conn = conn, state == .connected else {
            throw NSError(domain: "LocalNetworkTransport", code: 500, userInfo: [NSLocalizedDescriptionKey: "Transport not connected"])
        }

        let packetPayloadLength = 1 + msgData.count
        var lengthBigEndian = UInt32(packetPayloadLength).bigEndian
        var packetData = Data(bytes: &lengthBigEndian, count: 4)
        packetData.append(LocalNetworkTransport.tagProtocolMessage)
        packetData.append(msgData)

        try await sendData(packetData, on: conn)
    }

    /// Send raw video frame directly as binary payload (encoded with 0x02 tag, zero JSON overhead).
    public func sendMediaFrame(_ frameData: Data, timestamp: Double) async throws {
        let conn = withStateLock { connection }
        guard let conn = conn, state == .connected else {
            throw NSError(domain: "LocalNetworkTransport", code: 500, userInfo: [NSLocalizedDescriptionKey: "Transport not connected"])
        }

        var timestampBits = timestamp.bitPattern.bigEndian
        let timestampData = Data(bytes: &timestampBits, count: 8)

        let packetPayloadLength = 1 + 8 + frameData.count
        var lengthBigEndian = UInt32(packetPayloadLength).bigEndian

        var packetData = Data(capacity: 4 + packetPayloadLength)
        packetData.append(Data(bytes: &lengthBigEndian, count: 4))
        packetData.append(LocalNetworkTransport.tagMediaFrame)
        packetData.append(timestampData)
        packetData.append(frameData)

        try await sendData(packetData, on: conn)
    }

    private func sendData(_ data: Data, on conn: NWConnection) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    // MARK: - Message Reception & Stream Buffer

    private func startReceivingLoop() {
        lock.lock()
        guard !isReceiving else {
            lock.unlock()
            return
        }
        isReceiving = true
        let conn = connection
        lock.unlock()

        readMore(from: conn)
    }

    private func readMore(from conn: NWConnection?) {
        guard let conn = conn else { return }

        conn.receive(minimumIncompleteLength: 1, maximumLength: 131072) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let data = content, !data.isEmpty {
                self.processIncomingBytes(data)
            }

            if let error = error {
                self.lock.lock()
                self.state = .failed
                self.delegate?.transport(self, didFailWithError: error)
                self.lock.unlock()
                return
            }

            if isComplete {
                self.lock.lock()
                self.state = .disconnected
                self.delegate?.transport(self, didChangeState: .disconnected)
                self.lock.unlock()
                return
            }

            self.readMore(from: conn)
        }
    }

    /// Reassembles variable-length packets from TCP stream buffer.
    private func processIncomingBytes(_ data: Data) {
        lock.lock()
        receivedBuffer.append(data)

        while receivedBuffer.count >= 4 {
            let payloadLength = receivedBuffer.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let totalPacketSize = 4 + Int(payloadLength)

            guard receivedBuffer.count >= totalPacketSize else {
                // Incomplete packet in buffer; wait for remaining bytes from network
                break
            }

            let packetData = receivedBuffer.subdata(in: 4..<totalPacketSize)
            receivedBuffer.removeSubrange(0..<totalPacketSize)
            lock.unlock()

            dispatchPacket(packetData)

            lock.lock()
        }
        lock.unlock()
    }

    private func dispatchPacket(_ data: Data) {
        guard !data.isEmpty else { return }
        let tag = data[0]
        let payload = data.dropFirst()

        switch tag {
        case LocalNetworkTransport.tagProtocolMessage:
            if let message = try? ProtocolEngine.decode(Data(payload)) {
                delegate?.transport(self, didReceiveMessage: message)
            }
        case LocalNetworkTransport.tagMediaFrame:
            guard payload.count >= 8 else { return }
            let timestampData = payload.prefix(8)
            let frameData = payload.dropFirst(8)

            let timestampBits = timestampData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            let timestamp = Double(bitPattern: timestampBits)

            delegate?.transport(self, didReceiveMediaFrame: Data(frameData), timestamp: timestamp)
        default:
            print("[LocalNetworkTransport] Unknown packet tag: \(tag)")
        }
    }

    // MARK: - Teardown

    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }

        isReceiving = false
        receivedBuffer.removeAll()
        connection?.cancel()
        connection = nil
        state = .disconnected
        delegate?.transport(self, didChangeState: .disconnected)
    }
}
