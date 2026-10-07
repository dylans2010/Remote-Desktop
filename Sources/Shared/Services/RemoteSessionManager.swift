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
    #if os(macOS)
    private var activeCaptureEngine: ScreenCaptureEngine?
    #endif

    private func withStateLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }

    private init() {}

    /// Initiate a new remote desktop session with target device across network transport.
    public func startSession(with device: Device) async throws {
        withStateLock {
            activePeer = device
            updateState(.connecting)
        }

        let transport = LocalNetworkTransport()
        transport.delegate = self

        withStateLock {
            self.activeTransport = transport
        }

        try await transport.connect(to: device)

        #if os(macOS)
        // Host screen capture setup if host on macOS
        Task {
            let captureEngine = ScreenCaptureEngine()
            captureEngine.delegate = self
            withStateLock {
                self.activeCaptureEngine = captureEngine
            }
            try? await captureEngine.startCapture()
        }
        #elseif os(iOS)
        // Host screen capture setup if host on iOS
        Task { @MainActor in
            iOSBroadcastManager.shared.onFrameCaptured = { [weak self] frameData, timestamp in
                Task { [weak self] in
                    try? await self?.activeTransport?.sendMediaFrame(frameData, timestamp: timestamp)
                }
            }
        }
        #endif

        withStateLock {
            reconnectAttempts = 0
            updateState(.connected)
            startHeartbeat()
        }
    }

    // MARK: - ConnectionTransportDelegate

    public func transport(_ transport: ConnectionTransport, didChangeState state: TransportConnectionState) {
        withStateLock {
            updateState(state)
        }
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
            #if os(macOS)
            if let payload = message.payload, let event = try? JSONDecoder().decode(RemoteInputEvent.self, from: payload) {
                // Execute received input on REMOTE HOST machine
                RemoteInputEngine.shared.injectInputEvent(event)
            }
            #endif
        case .sessionOffer:
            if let payload = message.payload {
                delegate?.remoteSession(self, didReceiveFrame: payload, timestamp: message.timestamp.timeIntervalSince1970)
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
        withStateLock {
            if let pingTime = lastPingTime {
                roundTripLatencyMs = Date().timeIntervalSince(pingTime) * 1000.0
                delegate?.remoteSession(self, didUpdateMetrics: roundTripLatencyMs, bitrateMbps: 8.5)
            }
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
        let (shouldReconnect, peerToReconnect) = withStateLock { () -> (Bool, Device?) in
            guard currentState == .connected else {
                return (false, nil)
            }
            updateState(.reconnecting)
            reconnectAttempts += 1
            if reconnectAttempts <= maxReconnectAttempts {
                return (true, activePeer)
            } else {
                updateState(.failed)
                return (false, nil)
            }
        }

        if shouldReconnect, let peer = peerToReconnect {
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                try? await self.startSession(with: peer)
            }
        }
    }

    /// Terminate current active remote desktop session.
    public func endSession() {
        #if os(macOS)
        let capture = withStateLock { () -> ScreenCaptureEngine? in
            let c = self.activeCaptureEngine
            self.activeCaptureEngine = nil
            return c
        }
        Task {
            try? await capture?.stopCapture()
        }
        #elseif os(iOS)
        iOSBroadcastManager.shared.stopBroadcast()
        #endif

        withStateLock {
            stopHeartbeat()
            activeTransport?.disconnect()
            activeTransport = nil
            activePeer = nil
            updateState(.disconnected)
        }
    }

    private func updateState(_ state: TransportConnectionState) {
        currentState = state
        delegate?.remoteSession(self, didChangeState: state)
    }

    private func startHeartbeat() {
        stopHeartbeat()
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let peer = self.withStateLock { () -> Device? in
                    self.lastPingTime = Date()
                    return self.activePeer
                }

                if let peer = peer {
                    let ping = ProtocolMessage(type: .ping, senderID: "local", targetID: peer.id)
                    let transport = self.activeTransport
                    Task {
                        try? await transport?.sendMessage(ping)
                    }
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

#if os(macOS)
extension RemoteSessionManager: FrameCaptureDelegate {
    public func frameCaptureEngine(_ engine: ScreenCaptureEngine, didCaptureFrame frameData: Data, timestamp: Double) {
        Task {
            try? await activeTransport?.sendMediaFrame(frameData, timestamp: timestamp)
        }
    }
}
#endif
