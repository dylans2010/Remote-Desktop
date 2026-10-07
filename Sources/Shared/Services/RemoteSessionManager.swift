import Foundation
#if canImport(Network)
import Network
#endif

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Delegate protocol for remote desktop session state updates, frames, permissions, and metrics.
public protocol RemoteSessionDelegate: AnyObject {
    func remoteSession(_ session: RemoteSessionManager, didChangeState state: SessionState)
    func remoteSession(_ session: RemoteSessionManager, didReceiveFrame frameData: Data, timestamp: Double)
    func remoteSession(_ session: RemoteSessionManager, didUpdatePermissions permissions: RemoteSessionPermissions)
    func remoteSession(_ session: RemoteSessionManager, didUpdateHealth metrics: MediaHealthMetrics)
    func remoteSession(_ session: RemoteSessionManager, didReceiveAnnotation stroke: AnnotationStroke, action: AnnotationAction)
    func remoteSession(_ session: RemoteSessionManager, didEncounterError error: Error)
    func remoteSessionDidEnd(_ session: RemoteSessionManager, reason: String, endedByHost: Bool)
}

/// Orchestrates session state machine, incoming approval, permissions enforcement, media pipeline, input validation, and orderly disconnect.
public final class RemoteSessionManager: ConnectionTransportDelegate, RemoteMediaSessionDelegate, @unchecked Sendable {
    public enum SessionRole: String, Codable, Sendable {
        case none
        case host          // This machine is being viewed/controlled
        case controller    // This machine is viewing/controlling a remote host
    }

    public static let shared = RemoteSessionManager()

    public weak var delegate: RemoteSessionDelegate?

    private(set) public var currentState: SessionState = .idle
    private(set) public var sessionRole: SessionRole = .none
    private(set) public var activePeer: Device?
    private(set) public var activePermissions: RemoteSessionPermissions = .standardDefault
    private(set) public var sessionStartTime: Date?

    public var activeTransport: ConnectionTransport?

    private var pingTimer: Timer?
    private var lastPingTime: Date?
    private var roundTripLatencyMs: Double = 0.0
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    private let lock = NSLock()

    #if os(macOS)
    private var activeCaptureEngine: ScreenCaptureEngine?
    #endif

    // Pending incoming connection callback while awaiting host user approval
    public var incomingApprovalHandler: ((Device, RemoteSessionPermissions, @escaping @Sendable (Bool, RemoteSessionPermissions) -> Void) -> Void)?

    private func withStateLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }

    private init() {
        RemoteMediaSession.shared.delegate = self
    }

    // MARK: - Controller: Start Session with Remote Host

    /// Controller initiates a connection request to a remote host device.
    public func startSession(with targetDevice: Device, requestedPermissions: RemoteSessionPermissions = .standardDefault) async throws {
        withStateLock {
            self.activePeer = targetDevice
            self.sessionRole = .controller
            self.activePermissions = requestedPermissions
            updateState(.connecting)
        }

        let transport = LocalNetworkTransport()
        transport.delegate = self

        withStateLock {
            self.activeTransport = transport
        }

        try await transport.connect(to: targetDevice)

        // Once network connected, send formal connectionRequest with capabilities
        withStateLock {
            updateState(.requestingPermission)
        }

        let localIdentity = DeviceIdentity()
        let requestPayload = ConnectionRequestPayload(
            requesterID: localIdentity.deviceID,
            requesterName: localIdentity.deviceName,
            requesterPlatform: localIdentity.platform,
            requestedPermissions: requestedPermissions,
            capabilities: localIdentity.platform == .macOS ? .macOSDefault : .iOSDefault
        )

        guard let payloadData = try? JSONEncoder().encode(requestPayload) else {
            throw NSError(domain: "RemoteSessionManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to encode connection request"])
        }

        let requestMessage = ProtocolMessage(
            type: .connectionRequest,
            senderID: localIdentity.deviceID,
            targetID: targetDevice.id,
            payload: payloadData
        )

        try await transport.sendMessage(requestMessage)

        withStateLock {
            updateState(.awaitingApproval)
        }
    }

    // MARK: - Host: Handle Incoming Peer Connection

    /// Called by network listener when a remote device connects to this host.
    public func handleIncomingConnection(_ nwConnection: Any) {
        #if canImport(Network)
        guard let connection = nwConnection as? NWConnection else { return }

        // If host is already occupied in an active session, decline immediately
        let isOccupied = withStateLock {
            return currentState.isActive
        }

        let transport = LocalNetworkTransport(acceptedConnection: connection)
        transport.delegate = self

        if isOccupied {
            print("[RemoteSessionManager] Rejecting incoming connection: Host is already in an active session.")
            let localIdentity = DeviceIdentity()
            let busyPayload = ConnectionResponsePayload(
                approved: false,
                hostID: localIdentity.deviceID,
                hostName: localIdentity.deviceName,
                grantedPermissions: .viewOnly,
                hostCapabilities: localIdentity.platform == .macOS ? .macOSDefault : .iOSDefault,
                rejectionReason: "This host is already in use by another session."
            )
            if let data = try? JSONEncoder().encode(busyPayload) {
                let msg = ProtocolMessage(type: .connectionResponse, senderID: "local", payload: data)
                Task {
                    try? await transport.sendMessage(msg)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    transport.disconnect()
                }
            }
            return
        }

        withStateLock {
            self.activeTransport = transport
            self.sessionRole = .host
            updateState(.connecting)
        }
        #endif
    }

    // MARK: - ConnectionTransportDelegate

    public func transport(_ transport: ConnectionTransport, didChangeState state: TransportConnectionState) {
        withStateLock {
            if state == .failed {
                updateState(.transportFailed)
            } else if state == .disconnected && currentState != .disconnected {
                updateState(.disconnected)
            }
        }
    }

    public func transport(_ transport: ConnectionTransport, didReceiveMessage message: ProtocolMessage) {
        switch message.type {
        case .connectionRequest:
            handleIncomingConnectionRequest(message)

        case .connectionResponse:
            handleIncomingConnectionResponse(message)

        case .permissionUpdate:
            handlePermissionUpdate(message)

        case .permissionRevoked:
            handlePermissionRevocation(message)

        case .inputEvent:
            handleIncomingInputEvent(message)

        case .annotation:
            handleIncomingAnnotation(message)

        case .clipboardSync:
            handleClipboardSync(message)

        case .ping:
            if let pong = handlePing() {
                Task { try? await activeTransport?.sendMessage(pong) }
            }

        case .pong:
            handlePong()

        case .disconnectRequest:
            handleDisconnectRequest(message)

        case .disconnectAck, .sessionEnded:
            handleSessionEnded(message)

        case .sessionOffer:
            if let payload = message.payload {
                RemoteMediaSession.shared.receiveVideoFrame(payload, timestamp: message.timestamp.timeIntervalSince1970)
            }

        default:
            break
        }
    }

    public func transport(_ transport: ConnectionTransport, didReceiveMediaFrame frameData: Data, timestamp: Double) {
        RemoteMediaSession.shared.receiveVideoFrame(frameData, timestamp: timestamp)
    }

    public func transport(_ transport: ConnectionTransport, didFailWithError error: Error) {
        delegate?.remoteSession(self, didEncounterError: error)
        handleNetworkInterruption()
    }

    // MARK: - Connection Negotiation Handlers

    private func handleIncomingConnectionRequest(_ message: ProtocolMessage) {
        guard let payload = message.payload,
              let request = try? JSONDecoder().decode(ConnectionRequestPayload.self, from: payload) else {
            return
        }

        let requesterDevice = Device(
            id: request.requesterID,
            name: request.requesterName,
            platform: request.requesterPlatform,
            publicKeyData: Data(),
            capabilities: request.capabilities,
            trustStatus: TrustModel.shared.isTrusted(deviceID: request.requesterID) ? .trusted : .pendingApproval,
            onlineState: .online
        )

        withStateLock {
            self.activePeer = requesterDevice
            updateState(.awaitingApproval)
        }

        #if os(macOS)
        // Check if device is trusted with unattended access enabled
        if TrustModel.shared.isTrusted(deviceID: request.requesterID) && HostModeManager.shared.config.allowUnattendedAccess {
            let defaultPerms = TrustModel.shared.defaultPermissions(for: request.requesterID)
            self.respondToConnectionRequest(approved: true, permissions: defaultPerms)
            return
        }

        // Dispatch approval prompt to host UI and local notification
        if let customApproval = incomingApprovalHandler {
            customApproval(requesterDevice, request.requestedPermissions) { [weak self] approved, grantedPermissions in
                self?.respondToConnectionRequest(approved: approved, permissions: grantedPermissions)
            }
        } else {
            HostModeManager.shared.handleIncomingSessionRequest(from: requesterDevice) { [weak self] approved in
                let perms = approved ? request.requestedPermissions : .viewOnly
                self?.respondToConnectionRequest(approved: approved, permissions: perms)
            }
        }
        #elseif os(iOS)
        if let customApproval = incomingApprovalHandler {
            customApproval(requesterDevice, request.requestedPermissions) { [weak self] approved, grantedPermissions in
                self?.respondToConnectionRequest(approved: approved, permissions: grantedPermissions)
            }
        } else {
            let isTrusted = TrustModel.shared.isTrusted(deviceID: request.requesterID)
            let perms = isTrusted ? TrustModel.shared.defaultPermissions(for: request.requesterID) : request.requestedPermissions
            self.respondToConnectionRequest(approved: isTrusted, permissions: perms)
        }
        #endif
    }

    /// Host responds to an incoming connection request with approval decision and granted permissions.
    public func respondToConnectionRequest(approved: Bool, permissions: RemoteSessionPermissions) {
        withStateLock {
            self.activePermissions = permissions
        }

        let localIdentity = DeviceIdentity()
        let responsePayload = ConnectionResponsePayload(
            approved: approved,
            hostID: localIdentity.deviceID,
            hostName: localIdentity.deviceName,
            grantedPermissions: permissions,
            hostCapabilities: localIdentity.platform == .macOS ? .macOSDefault : .iOSDefault,
            rejectionReason: approved ? nil : "Host declined connection request."
        )

        guard let payloadData = try? JSONEncoder().encode(responsePayload) else { return }
        let responseMsg = ProtocolMessage(
            type: .connectionResponse,
            senderID: localIdentity.deviceID,
            targetID: activePeer?.id,
            payload: payloadData
        )

        Task {
            try? await activeTransport?.sendMessage(responseMsg)

            if approved {
                withStateLock {
                    self.sessionStartTime = Date()
                    updateState(.establishingMedia)
                }
                startHostScreenStreaming()
            } else {
                withStateLock {
                    updateState(.permissionDenied)
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                endSession(reason: "Declined by user")
            }
        }
    }

    private func handleIncomingConnectionResponse(_ message: ProtocolMessage) {
        guard let payload = message.payload,
              let response = try? JSONDecoder().decode(ConnectionResponsePayload.self, from: payload) else {
            return
        }

        if response.approved {
            withStateLock {
                self.activePermissions = response.grantedPermissions
                self.sessionStartTime = Date()
                updateState(.establishingMedia)
            }

            // Start media session in controller role
            RemoteMediaSession.shared.start(role: .controller)
            startHeartbeat()

            print("[RemoteSessionManager] Connection approved by host with permissions: \(response.grantedPermissions)")
        } else {
            withStateLock {
                updateState(.permissionDenied)
            }
            print("[RemoteSessionManager] Connection rejected: \(response.rejectionReason ?? "Unknown")")
            endSession(reason: response.rejectionReason ?? "Connection rejected by host")
        }
    }

    // MARK: - Host Screen Streaming Lifecycle

    private func startHostScreenStreaming() {
        #if os(macOS)
        Task {
            let captureEngine = ScreenCaptureEngine()
            captureEngine.delegate = self
            withStateLock {
                self.activeCaptureEngine = captureEngine
            }

            RemoteMediaSession.shared.start(role: .host) { [weak self] frameData, timestamp in
                try await self?.activeTransport?.sendMediaFrame(frameData, timestamp: timestamp)
            }

            do {
                try await captureEngine.startCapture()
                withStateLock {
                    updateState(.connected)
                    startHeartbeat()
                }
            } catch {
                print("[RemoteSessionManager] Screen capture failed to start: \(error)")
                withStateLock {
                    updateState(.captureUnavailable)
                }
            }
        }
        #elseif os(iOS)
        RemoteMediaSession.shared.start(role: .host) { [weak self] frameData, timestamp in
            try await self?.activeTransport?.sendMediaFrame(frameData, timestamp: timestamp)
        }
        iOSBroadcastManager.shared.onFrameCaptured = { frameData, timestamp in
            Task {
                try? await RemoteMediaSession.shared.sendVideoFrame(frameData, timestamp: timestamp)
            }
        }
        withStateLock {
            updateState(.connected)
            startHeartbeat()
        }
        #endif
    }

    // MARK: - Permission Management & Dynamic Updating

    /// Host dynamically updates permissions during an active session.
    public func updateSessionPermissions(_ newPermissions: RemoteSessionPermissions, reason: String? = nil) {
        guard sessionRole == .host else { return }

        withStateLock {
            self.activePermissions = newPermissions
        }

        delegate?.remoteSession(self, didUpdatePermissions: newPermissions)

        let payload = PermissionUpdatePayload(updatedPermissions: newPermissions, reason: reason)
        if let data = try? JSONEncoder().encode(payload), let peer = activePeer {
            let msg = ProtocolMessage(type: .permissionUpdate, senderID: "host", targetID: peer.id, payload: data)
            Task {
                try? await activeTransport?.sendMessage(msg)
            }
        }
    }

    private func handlePermissionUpdate(_ message: ProtocolMessage) {
        guard let payload = message.payload,
              let update = try? JSONDecoder().decode(PermissionUpdatePayload.self, from: payload) else {
            return
        }

        withStateLock {
            self.activePermissions = update.updatedPermissions
        }

        delegate?.remoteSession(self, didUpdatePermissions: update.updatedPermissions)
        print("[RemoteSessionManager] Permissions dynamically updated by host: \(update.updatedPermissions)")
    }

    private func handlePermissionRevocation(_ message: ProtocolMessage) {
        withStateLock {
            self.activePermissions = .viewOnly
        }
        delegate?.remoteSession(self, didUpdatePermissions: .viewOnly)
    }

    // MARK: - Input Validation & Injection (Host-Enforced)

    private func handleIncomingInputEvent(_ message: ProtocolMessage) {
        // Enforce permissions strictly on the host side
        guard sessionRole == .host, currentState == .connected else { return }
        guard activePermissions.controlScreen else {
            print("[RemoteSessionManager] Input event dropped: controlScreen permission disabled")
            return
        }

        guard let payload = message.payload,
              let event = try? JSONDecoder().decode(RemoteInputEvent.self, from: payload) else {
            return
        }

        guard activePermissions.isInputAuthorized(for: event.type) else {
            print("[RemoteSessionManager] Input event dropped: \(event.type) not authorized")
            return
        }

        #if os(macOS)
        guard AccessibilityPermissionManager.shared.isAuthorized else {
            print("[RemoteSessionManager] Input event dropped: Accessibility permission missing on host")
            return
        }
        RemoteInputEngine.shared.injectInputEvent(event)
        #endif
    }

    /// Controller transmits remote input to host.
    public func sendRemoteInput(_ event: RemoteInputEvent) {
        guard sessionRole == .controller, currentState == .connected else { return }
        guard activePermissions.isInputAuthorized(for: event.type) else { return }

        guard let payload = try? JSONEncoder().encode(event), let peer = activePeer else { return }
        let msg = ProtocolMessage(type: .inputEvent, senderID: "local", targetID: peer.id, payload: payload)
        Task {
            try? await activeTransport?.sendMessage(msg)
        }
    }

    // MARK: - Drawing & Annotations

    /// Transmit annotation action across session.
    public func sendAnnotation(stroke: AnnotationStroke? = nil, action: AnnotationAction, point: NormalizedPoint? = nil) {
        guard activePermissions.isAnnotationAuthorized else { return }

        let payload = AnnotationMessagePayload(action: action, stroke: stroke, point: point)
        guard let data = try? JSONEncoder().encode(payload), let peer = activePeer else { return }

        let msg = ProtocolMessage(type: .annotation, senderID: "local", targetID: peer.id, payload: data)
        Task {
            try? await activeTransport?.sendMessage(msg)
        }
    }

    private func handleIncomingAnnotation(_ message: ProtocolMessage) {
        guard activePermissions.isAnnotationAuthorized else { return }
        guard let payload = message.payload,
              let annotationData = try? JSONDecoder().decode(AnnotationMessagePayload.self, from: payload) else {
            return
        }

        if let stroke = annotationData.stroke {
            delegate?.remoteSession(self, didReceiveAnnotation: stroke, action: annotationData.action)
        }
    }

    // MARK: - Clipboard Synchronization

    private func handleClipboardSync(_ message: ProtocolMessage) {
        guard activePermissions.isClipboardAuthorized else { return }
        if let payload = message.payload,
           let clipboardPayload = try? JSONDecoder().decode(ClipboardPayload.self, from: payload) {
            ClipboardSyncManager.shared.applyRemoteClipboard(clipboardPayload)
        }
    }

    // MARK: - Disconnect Handshake & Teardown

    /// Gracefully end the remote session from either Host or Controller.
    public func endSession(reason: String = "User requested disconnect") {
        let isHost = (sessionRole == .host)
        let peer = activePeer

        // Send disconnect notice across authenticated transport
        if let peer = peer {
            if isHost {
                let payload = SessionEndedPayload(reason: reason, endedByHost: true)
                if let data = try? JSONEncoder().encode(payload) {
                    let msg = ProtocolMessage(type: .sessionEnded, senderID: "host", targetID: peer.id, payload: data)
                    Task { try? await activeTransport?.sendMessage(msg) }
                }
            } else {
                let payload = DisconnectPayload(reason: reason, requestedBy: "controller")
                if let data = try? JSONEncoder().encode(payload) {
                    let msg = ProtocolMessage(type: .disconnectRequest, senderID: "controller", targetID: peer.id, payload: data)
                    Task { try? await activeTransport?.sendMessage(msg) }
                }
            }
        }

        performCompleteCleanup(reason: reason, endedByHost: isHost)
    }

    private func handleDisconnectRequest(_ message: ProtocolMessage) {
        let isHost = (sessionRole == .host)
        let ackMsg = ProtocolMessage(type: .disconnectAck, senderID: "local")
        Task { try? await activeTransport?.sendMessage(ackMsg) }

        performCompleteCleanup(reason: "Remote peer disconnected", endedByHost: false)
    }

    private func handleSessionEnded(_ message: ProtocolMessage) {
        var reason = "Remote session ended"
        var endedByHost = false

        if let payload = message.payload, let endedPayload = try? JSONDecoder().decode(SessionEndedPayload.self, from: payload) {
            reason = endedPayload.reason
            endedByHost = endedPayload.endedByHost
        }

        performCompleteCleanup(reason: reason, endedByHost: endedByHost)
    }

    /// Complete teardown of media tracks, screen capture, transport, and session state.
    private func performCompleteCleanup(reason: String, endedByHost: Bool) {
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

        RemoteMediaSession.shared.stop()

        withStateLock {
            stopHeartbeat()
            activeTransport?.disconnect()
            activeTransport = nil
            activePeer = nil
            sessionRole = .none
            sessionStartTime = nil
            updateState(.disconnected)
        }

        delegate?.remoteSessionDidEnd(self, reason: reason, endedByHost: endedByHost)
        print("[RemoteSessionManager] Session completely cleaned up. Reason: \(reason)")
    }

    /// Handles trust revocation for an active device.
    public func handleTrustRevocation(deviceID: String) {
        let shouldTerminate = withStateLock { () -> Bool in
            return activePeer?.id == deviceID && currentState.isActive
        }
        if shouldTerminate {
            print("[RemoteSessionManager] Device trust revoked for active peer. Terminating session immediately.")
            endSession(reason: "Device trust was revoked.")
        }
    }

    // MARK: - Heartbeat & Metrics

    public func handlePing() -> ProtocolMessage? {
        guard let peer = activePeer else { return nil }
        return ProtocolMessage(type: .pong, senderID: "local", targetID: peer.id)
    }

    public func handlePong() {
        withStateLock {
            if let pingTime = lastPingTime {
                roundTripLatencyMs = Date().timeIntervalSince(pingTime) * 1000.0
                RemoteMediaSession.shared.updateRTT(roundTripLatencyMs)
            }
        }
    }

    private func startHeartbeat() {
        stopHeartbeat()
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
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

    public func handleNetworkInterruption() {
        let (shouldReconnect, peerToReconnect) = withStateLock { () -> (Bool, Device?) in
            guard currentState == .connected else { return (false, nil) }
            updateState(.reconnecting)
            reconnectAttempts += 1
            if reconnectAttempts <= maxReconnectAttempts {
                return (true, activePeer)
            } else {
                updateState(.transportFailed)
                return (false, nil)
            }
        }

        if shouldReconnect, let peer = peerToReconnect {
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                try? await self.startSession(with: peer, requestedPermissions: self.activePermissions)
            }
        }
    }

    private func updateState(_ state: SessionState) {
        currentState = state
        delegate?.remoteSession(self, didChangeState: state)
    }

    // MARK: - RemoteMediaSessionDelegate

    public func mediaSession(_ session: RemoteMediaSession, didReceiveDecodedFrame frameData: Data, timestamp: Double) {
        // If controller received first frame, transition state from establishingMedia to connected
        withStateLock {
            if currentState == .establishingMedia && sessionRole == .controller {
                updateState(.connected)
            }
        }
        delegate?.remoteSession(self, didReceiveFrame: frameData, timestamp: timestamp)
    }

    public func mediaSession(_ session: RemoteMediaSession, didUpdateHealth metrics: MediaHealthMetrics) {
        delegate?.remoteSession(self, didUpdateHealth: metrics)
    }

    public func mediaSessionDidStall(_ session: RemoteMediaSession, stage: PipelineDiagnosticStage) {
        print("[RemoteSessionManager] Media pipeline stalled at stage: \(stage.rawValue)")
    }
}

#if os(macOS)
extension RemoteSessionManager: FrameCaptureDelegate {
    public func frameCaptureEngine(_ engine: ScreenCaptureEngine, didCaptureFrame frameData: Data, timestamp: Double) {
        Task {
            try? await RemoteMediaSession.shared.sendVideoFrame(frameData, timestamp: timestamp)
        }
    }

    public func frameCaptureEngineDidFail(_ engine: ScreenCaptureEngine, error: Error) {
        withStateLock {
            updateState(.captureUnavailable)
        }
        delegate?.remoteSession(self, didEncounterError: error)
    }
}
#endif
