import Foundation
import Network

/// Concrete connection transport implementation using Network.framework NWConnection.
/// Enforces formal TransportState machine, asynchronous readiness guarantees, and channel multiplexing.
public final class LocalNetworkTransport: ConnectionTransport, RemoteTransport, @unchecked Sendable {
    public private(set) var state: TransportState = .idle
    public private(set) var transportMode: TransportMode = .localLAN
    public var sessionID: SessionID?
    public weak var delegate: ConnectionTransportDelegate?
    public private(set) var diagnostics = TransportDiagnostics()

    private var connection: NWConnection?
    private let lock = NSLock()
    private var receivedBuffer = Data()
    private var isReceiving = false

    private var activePeerName: String?
    private var activeEndpointString: String?

    // Async readiness synchronization (Requirement 5 & 6)
    private var readyContinuations: [CheckedContinuation<Void, Error>] = []
    private var connectContinuation: CheckedContinuation<Void, Error>?

    // Raw binary receive queue for RemoteTransport protocol conformance
    private var rawReceiveContinuations: [CheckedContinuation<Data, Error>] = []
    private var rawReceiveBuffer: [Data] = []

    // Packet type tags (Channel mappings)
    public static let tagProtocolMessage: UInt8 = TransportChannel.control.rawValue
    public static let tagMediaFrame: UInt8 = TransportChannel.mediaVideo.rawValue

    private func withStateLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }

    /// Client initializer for connecting out to a peer.
    public init() {
        print("[TRANSPORT] Created")
    }

    /// Server initializer for wrapping an incoming accepted NWConnection.
    public init(acceptedConnection: NWConnection) {
        self.connection = acceptedConnection
        print("[TRANSPORT] Created (Accepted inbound connection)")
        transition(to: .connecting)
        setupConnection(acceptedConnection, peerName: "Inbound Peer", endpointString: acceptedConnection.endpoint.debugDescription)
    }

    // MARK: - State Transitions & Logging (Requirement 17)

    private func transition(to newState: TransportState) {
        withStateLock {
            self.state = newState
            self.diagnostics.state = newState

            switch newState {
            case .idle:
                print("[TRANSPORT] Idle")
            case .connecting:
                print("[TRANSPORT] Connecting")
            case .authenticating:
                print("[TRANSPORT] Authenticating")
            case .negotiating:
                print("[TRANSPORT] Negotiating capabilities")
            case .ready:
                print("[TRANSPORT] READY")
            case .reconnecting:
                print("[TRANSPORT] Reconnecting")
            case .disconnecting:
                print("[TRANSPORT] Disconnecting")
            case .disconnected:
                print("[TRANSPORT] Disconnected")
            case .failed(let err):
                print("[TRANSPORT] FAILED: \(err.localizedDescription)")
            }

            // If terminal failure or disconnection, fail pending continuations
            if case .failed(let err) = newState {
                let continuations = self.readyContinuations
                self.readyContinuations.removeAll()
                for cont in continuations {
                    cont.resume(throwing: err)
                }

                if let connCont = self.connectContinuation {
                    self.connectContinuation = nil
                    connCont.resume(throwing: err)
                }

                let rawConts = self.rawReceiveContinuations
                self.rawReceiveContinuations.removeAll()
                for cont in rawConts {
                    cont.resume(throwing: err)
                }
            } else if newState == .disconnected {
                let err = TransportError.sessionTerminated(reason: "Transport connection closed")
                let continuations = self.readyContinuations
                self.readyContinuations.removeAll()
                for cont in continuations {
                    cont.resume(throwing: err)
                }

                if let connCont = self.connectContinuation {
                    self.connectContinuation = nil
                    connCont.resume(throwing: err)
                }
            }
        }

        delegate?.transport(self, didChangeState: newState)
    }

    // MARK: - Outbound Connection (Requirement 4 & 7)

    /// Connect out to a remote peer device over TCP. Waits for NWConnection to be established.
    public func connect(to peer: Device) async throws {
        transition(to: .connecting)
        withStateLock {
            self.diagnostics.connectionStartedAt = Date()
            self.activePeerName = peer.name
        }

        guard let host = peer.ipAddress else {
            let error = TransportError.connectionFailed(
                peer: peer.name,
                endpoint: "None",
                underlying: NSError(domain: "LocalNetworkTransport", code: 400, userInfo: [NSLocalizedDescriptionKey: "Peer IP address missing"])
            )
            withStateLock { self.diagnostics.lastError = error.localizedDescription }
            transition(to: .failed(error))
            throw error
        }

        let portNumber = peer.port ?? 58900
        let endpointString = "\(host):\(portNumber)"
        withStateLock { self.activeEndpointString = endpointString }

        let port = NWEndpoint.Port(rawValue: portNumber) ?? 58900
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableFastOpen = false
        tcpOptions.noDelay = true // Disable Nagle's algorithm for low-latency desktop input/video

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.includePeerToPeer = true

        let nwConn = NWConnection(to: endpoint, using: params)
        withStateLock {
            self.connection = nwConn
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            withStateLock {
                self.connectContinuation = continuation
            }
            setupConnection(nwConn, peerName: peer.name, endpointString: endpointString)
        }
    }

    /// Configures state handler and starts receiving from connection.
    private func setupConnection(_ nwConn: NWConnection, peerName: String, endpointString: String) {
        nwConn.stateUpdateHandler = { [weak self] connState in
            guard let self = self else { return }

            switch connState {
            case .preparing:
                print("[TRANSPORT] NWConnection preparing")

            case .waiting(let err):
                print("[TRANSPORT] NWConnection waiting: \(err.localizedDescription)")

            case .ready:
                print("[TRANSPORT] NWConnection ready (TCP established)")
                let continuationToResume = self.withStateLock { () -> CheckedContinuation<Void, Error>? in
                    self.diagnostics.connectedAt = Date()
                    let cont = self.connectContinuation
                    self.connectContinuation = nil
                    return cont
                }

                self.startReceivingLoop()
                continuationToResume?.resume()

            case .failed(let err):
                print("[TRANSPORT] NWConnection failed: \(err.localizedDescription)")
                let customErr = TransportError.connectionFailed(
                    peer: peerName,
                    endpoint: endpointString,
                    underlying: err
                )
                self.withStateLock {
                    self.diagnostics.lastError = customErr.localizedDescription
                }
                self.transition(to: .failed(customErr))

            case .cancelled:
                print("[TRANSPORT] NWConnection cancelled")
                self.transition(to: .disconnected)

            @unknown default:
                break
            }
        }

        nwConn.start(queue: .global(qos: .userInteractive))
    }

    // MARK: - Explicit Readiness Mechanism (Requirement 6)

    /// Await until the transport genuinely completes required handshake and transitions to .ready.
    public func waitUntilReady() async throws {
        let currentState = withStateLock { self.state }
        switch currentState {
        case .ready:
            return
        case .failed(let err):
            throw err
        case .disconnected:
            throw TransportError.sessionTerminated(reason: "Transport is disconnected")
        case .idle, .connecting, .authenticating, .negotiating, .reconnecting, .disconnecting:
            try await withCheckedThrowingContinuation { continuation in
                withStateLock {
                    if self.state == .ready {
                        continuation.resume()
                    } else if case .failed(let err) = self.state {
                        continuation.resume(throwing: err)
                    } else if self.state == .disconnected {
                        continuation.resume(throwing: TransportError.sessionTerminated(reason: "Transport is disconnected"))
                    } else {
                        self.readyContinuations.append(continuation)
                    }
                }
            }
        }
    }

    /// Mark transport as authenticated, negotiated, and fully ready.
    public func markReady() {
        let continuationsToResume = withStateLock { () -> [CheckedContinuation<Void, Error>] in
            guard self.state != .ready else { return [] }
            self.diagnostics.readyAt = Date()
            let conts = self.readyContinuations
            self.readyContinuations.removeAll()
            return conts
        }

        transition(to: .ready)

        for cont in continuationsToResume {
            cont.resume()
        }
    }

    /// Update higher-level state during handshake progression.
    public func updateHandshakeState(_ newState: TransportState) {
        transition(to: newState)
    }

    // MARK: - Message Transmission (Requirement 10 & 13)

    private func channelTag(for message: ProtocolMessage) -> UInt8 {
        if let explicitChannel = message.channel {
            return explicitChannel.rawValue
        }
        switch message.type {
        case .hello, .helloAck, .ping, .pong, .disconnect, .disconnectRequest, .disconnectAck, .sessionEnded:
            return TransportChannel.control.rawValue
        case .authChallenge, .authResponse, .pairRequest, .pairAccepted, .pairRejected:
            return TransportChannel.authentication.rawValue
        case .sessionNegotiation, .sessionAccepted, .sessionOffer, .sessionAnswer, .connectionRequest, .connectionResponse, .permissionUpdate, .permissionRevoked, .sessionRequest, .sessionRejected, .iceCandidate:
            return TransportChannel.session.rawValue
        case .inputEvent:
            return TransportChannel.input.rawValue
        case .annotation:
            return TransportChannel.annotation.rawValue
        case .clipboardSync:
            return TransportChannel.clipboard.rawValue
        case .fileOffer, .fileAccept, .fileChunk, .fileComplete, .fileCancel:
            return TransportChannel.fileTransfer.rawValue
        }
    }

    /// Send a structured protocol message over the appropriate logical channel.
    public func sendMessage(_ message: ProtocolMessage) async throws {
        let conn = withStateLock { connection }
        let currentState = withStateLock { state }

        guard let conn = conn else {
            throw TransportError.notReady(state: currentState, sessionID: sessionID, peerName: activePeerName)
        }

        // Allow sending messages during connecting/authenticating/negotiating (for handshake) or when ready
        guard currentState == .ready || currentState == .connecting || currentState == .authenticating || currentState == .negotiating else {
            throw TransportError.notReady(state: currentState, sessionID: sessionID, peerName: activePeerName)
        }

        let msgData = try ProtocolEngine.encode(message)
        let tag = channelTag(for: message)

        let packetPayloadLength = 1 + msgData.count
        var lengthBigEndian = UInt32(packetPayloadLength).bigEndian
        var packetData = Data(capacity: 4 + packetPayloadLength)
        packetData.append(Data(bytes: &lengthBigEndian, count: 4))
        packetData.append(tag)
        packetData.append(msgData)

        try await sendData(packetData, on: conn)

        withStateLock {
            self.diagnostics.bytesSent += UInt64(packetData.count)
            self.diagnostics.messagesSent += 1
            self.diagnostics.lastSend = Date()
        }
    }

    /// Send raw video frame directly as binary payload. Strictly requires transport to be ready.
    public func sendMediaFrame(_ frameData: Data, timestamp: Double) async throws {
        let conn = withStateLock { connection }
        let currentState = withStateLock { state }

        guard let conn = conn, currentState == .ready else {
            print("[MEDIA] Media attempted to send frame while transport state is \(currentState.description)")
            throw TransportError.notReady(state: currentState, sessionID: sessionID, peerName: activePeerName)
        }

        var timestampBits = timestamp.bitPattern.bigEndian
        let timestampData = Data(bytes: &timestampBits, count: 8)

        let packetPayloadLength = 1 + 8 + frameData.count
        var lengthBigEndian = UInt32(packetPayloadLength).bigEndian

        var packetData = Data(capacity: 4 + packetPayloadLength)
        packetData.append(Data(bytes: &lengthBigEndian, count: 4))
        packetData.append(TransportChannel.mediaVideo.rawValue)
        packetData.append(timestampData)
        packetData.append(frameData)

        try await sendData(packetData, on: conn)

        withStateLock {
            self.diagnostics.bytesSent += UInt64(packetData.count)
            self.diagnostics.lastSend = Date()
        }
    }

    /// RemoteTransport generic binary send
    public func send(_ data: Data) async throws {
        let conn = withStateLock { connection }
        let currentState = withStateLock { state }

        guard let conn = conn, currentState == .ready || currentState == .connecting || currentState == .authenticating || currentState == .negotiating else {
            throw TransportError.notReady(state: currentState, sessionID: sessionID, peerName: activePeerName)
        }

        let packetPayloadLength = 1 + data.count
        var lengthBigEndian = UInt32(packetPayloadLength).bigEndian
        var packetData = Data(capacity: 4 + packetPayloadLength)
        packetData.append(Data(bytes: &lengthBigEndian, count: 4))
        packetData.append(TransportChannel.control.rawValue)
        packetData.append(data)

        try await sendData(packetData, on: conn)

        withStateLock {
            self.diagnostics.bytesSent += UInt64(packetData.count)
            self.diagnostics.messagesSent += 1
            self.diagnostics.lastSend = Date()
        }
    }

    /// RemoteTransport generic binary receive
    public func receive() async throws -> Data {
        let bufferedData = withStateLock { () -> Data? in
            if !self.rawReceiveBuffer.isEmpty {
                return self.rawReceiveBuffer.removeFirst()
            }
            return nil
        }

        if let buffered = bufferedData {
            return buffered
        }

        return try await withCheckedThrowingContinuation { continuation in
            withStateLock {
                self.rawReceiveContinuations.append(continuation)
            }
        }
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
        withStateLock {
            guard !isReceiving else { return }
            isReceiving = true
        }

        let conn = withStateLock { connection }
        readMore(from: conn)
    }

    private func readMore(from conn: NWConnection?) {
        guard let conn = conn else { return }

        conn.receive(minimumIncompleteLength: 1, maximumLength: 131072) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let data = content, !data.isEmpty {
                self.withStateLock {
                    self.diagnostics.bytesReceived += UInt64(data.count)
                    self.diagnostics.lastReceive = Date()
                }
                self.processIncomingBytes(data)
            }

            if let error = error {
                let wrappedErr = TransportError.connectionFailed(
                    peer: self.activePeerName ?? "Peer",
                    endpoint: self.activeEndpointString ?? "Unknown",
                    underlying: error
                )
                self.withStateLock {
                    self.diagnostics.lastError = wrappedErr.localizedDescription
                }
                self.transition(to: .failed(wrappedErr))
                self.delegate?.transport(self, didFailWithError: wrappedErr)
                return
            }

            if isComplete {
                self.transition(to: .disconnected)
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
                // Incomplete packet in buffer; wait for remaining bytes
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

        if tag == TransportChannel.mediaVideo.rawValue || tag == 0x02 {
            // Media Frame Channel
            guard payload.count >= 8 else { return }
            let timestampData = payload.prefix(8)
            let frameData = payload.dropFirst(8)

            let timestampBits = timestampData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            let timestamp = Double(bitPattern: timestampBits)

            delegate?.transport(self, didReceiveMediaFrame: Data(frameData), timestamp: timestamp)
        } else {
            // Control, Authentication, Session, Input, Annotation, Clipboard, FileTransfer
            let payloadData = Data(payload)

            // Fulfill any waiting raw binary receivers
            let rawCont = withStateLock { () -> CheckedContinuation<Data, Error>? in
                if !self.rawReceiveContinuations.isEmpty {
                    return self.rawReceiveContinuations.removeFirst()
                } else {
                    self.rawReceiveBuffer.append(payloadData)
                    return nil
                }
            }
            rawCont?.resume(returning: payloadData)

            if let message = try? ProtocolEngine.decode(payloadData) {
                withStateLock {
                    self.diagnostics.messagesReceived += 1
                }
                delegate?.transport(self, didReceiveMessage: message)
            }
        }
    }

    // MARK: - Teardown

    public func disconnect() {
        lock.lock()
        isReceiving = false
        receivedBuffer.removeAll()
        rawReceiveBuffer.removeAll()
        let activeConn = connection
        connection = nil
        lock.unlock()

        activeConn?.cancel()
        transition(to: .disconnected)
    }
}
