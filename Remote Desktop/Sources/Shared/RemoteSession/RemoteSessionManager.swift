import Foundation

/// Delegate protocol for remote desktop session state updates and metrics.
public protocol RemoteSessionDelegate: AnyObject {
    func remoteSession(_ session: RemoteSessionManager, didChangeState state: TransportConnectionState)
    func remoteSession(_ session: RemoteSessionManager, didReceiveFrame frameData: Data, timestamp: Double)
    func remoteSession(_ session: RemoteSessionManager, didUpdateMetrics latencyMs: Double, bitrateMbps: Double)
    func remoteSession(_ session: RemoteSessionManager, didEncounterError error: Error)
}

/// Orchestrates session creation, handshake, network transport, video encoding/capture, heartbeat, and auto-reconnection.
public final class RemoteSessionManager: ConnectionTransportDelegate, @unchecked Sendable {
    public static let shared = RemoteSessionManager()

    public weak var delegate: RemoteSessionDelegate?

    private(set) public var currentState: TransportConnectionState = .disconnected
    private(set) public var currentTransportMode: TransportMode = .localLAN
    private(set) public var activePeer: Device?

    public var activeTransport: ConnectionTransport?
    private var pingTimer: Timer?
    private var lastPingTime: Date?
    private var roundTripLatencyMs: Double = 0.0
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private let lock = NSLock()

    private init() {}

    /// Initiate a new remote desktop session with target device across network transport.
    public func startSession(with device: Device) async throws {
        lock.lock()
        activePeer = device
        updateState(.connecting)
        lock.unlock()

        let transport = LocalNetworkTransport()
        transport.delegate = self

        lock.lock()
        self.activeTransport = transport
        lock.unlock()

        try await transport.connect(to: device)

        // Host screen capture setup if host
        Task {
            let captureEngine = ScreenCaptureEngine()
            captureEngine.delegate = self
            try? await captureEngine.startCapture()
        }

        lock.lock()
        reconnectAttempts = 0
        updateState(.connected)
        startHeartbeat()
        lock.unlock()
    }

    // MARK: - ConnectionTransportDelegate

    public func transport(_ transport: ConnectionTransport, didChangeState state: TransportConnectionState) {
        lock.lock()
        updateState(state)
        lock.unlock()
    }

    public func transport(_ transport: ConnectionTransport, didReceiveMessage message: ProtocolMessage) {
        switch message.type {
        case .ping:
            if let pong = handlePing() {
                Task { try? await activeTransport?.sendMessage(pong) }
            }
        case .pong:
            handlePong()
        case .inputEvent:
            if let payload = message.payload, let event = try? JSONDecoder().decode(RemoteInputEvent.self, from: payload) {
                // Execute received input on REMOTE HOST machine
                RemoteInputEngine.shared.injectInputEvent(event)
            }
        case .clipboardSync:
            if let payload = message.payload, let clipboardPayload = try? JSONDecoder().decode(ClipboardPayload.self, from: payload) {
                ClipboardSyncManager.shared.applyRemoteClipboard(clipboardPayload)
            }
        default:
            break
        }
    }

    public func transport(_ transport: ConnectionTransport, didReceiveMediaFrame frameData: Data, timestamp: Double) {
        delegate?.remoteSession(self, didReceiveFrame: frameData, timestamp: timestamp)
    }

    public func transport(_ transport: ConnectionTransport, didFailWithError error: Error) {
        delegate?.remoteSession(self, didEncounterError: error)
        handleNetworkInterruption()
    }

    /// Handle incoming ping message and send pong response.
    public func handlePing() -> ProtocolMessage? {
        guard let peer = activePeer else { return nil }
        return ProtocolMessage(type: .pong, senderID: "local", targetID: peer.id)
    }

    /// Handle incoming pong message and update latency calculation.
    public func handlePong() {
        lock.lock()
        defer { lock.unlock() }

        if let pingTime = lastPingTime {
            roundTripLatencyMs = Date().timeIntervalSince(pingTime) * 1000.0
            delegate?.remoteSession(self, didUpdateMetrics: roundTripLatencyMs, bitrateMbps: 8.5)
        }
    }

    /// Send remote input event across active network transport to remote peer.
    public func sendRemoteInput(_ event: RemoteInputEvent) {
        guard let payload = try? JSONEncoder().encode(event), let peer = activePeer else { return }
        let msg = ProtocolMessage(type: .inputEvent, senderID: "local", targetID: peer.id, payload: payload)
        Task {
            try? await activeTransport?.sendMessage(msg)
        }
    }

    /// Trigger reconnection flow on network interruption.
    public func handleNetworkInterruption() {
        lock.lock()
        guard currentState == .connected else {
            lock.unlock()
            return
        }

        updateState(.reconnecting)
        reconnectAttempts += 1
        let currentAttempts = reconnectAttempts
        lock.unlock()

        if currentAttempts <= maxReconnectAttempts {
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let peer = self.activePeer {
                    try? await self.startSession(with: peer)
                }
            }
        } else {
            lock.lock()
            updateState(.failed)
            lock.unlock()
        }
    }

    /// Terminate current active remote desktop session.
    public func endSession() {
        lock.lock()
        stopHeartbeat()
        activeTransport?.disconnect()
        activeTransport = nil
        activePeer = nil
        updateState(.disconnected)
        lock.unlock()
    }

    private func updateState(_ state: TransportConnectionState) {
        currentState = state
        delegate?.remoteSession(self, didChangeState: state)
    }

    private func startHeartbeat() {
        stopHeartbeat()
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                self?.lock.lock()
                self?.lastPingTime = Date()
                let peer = self?.activePeer
                self?.lock.unlock()

                if let peer = peer {
                    let ping = ProtocolMessage(type: .ping, senderID: "local", targetID: peer.id)
                    Task { try? await self?.activeTransport?.sendMessage(ping) }
                }
            }
        }
    }

    private func stopHeartbeat() {
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer?.invalidate()
            self?.pingTimer = nil
        }
    }
}

extension RemoteSessionManager: ScreenCaptureDelegate {
    public func screenCaptureEngine(_ engine: ScreenCaptureEngine, didCaptureFrame frameData: Data, timestamp: Double) {
        Task {
            try? await activeTransport?.sendMediaFrame(frameData, timestamp: timestamp)
        }
    }

    public func screenCaptureEngine(_ engine: ScreenCaptureEngine, didEncounterError error: Error) {
        print("[RemoteSessionManager] Screen capture engine error: \(error)")
    }
}
