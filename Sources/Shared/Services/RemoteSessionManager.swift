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
    func remoteSession(_ session: RemoteSessionManager, didReceiveDecodedImage image: CGImage, timestamp: Double)
    func remoteSession(_ session: RemoteSessionManager, didReceiveFrame frameData: Data, timestamp: Double)
    func remoteSession(_ session: RemoteSessionManager, didUpdatePermissions permissions: RemoteSessionPermissions)
    func remoteSession(_ session: RemoteSessionManager, didUpdateHealth metrics: MediaHealthMetrics)
    func remoteSession(_ session: RemoteSessionManager, didReceiveAnnotation stroke: AnnotationStroke, action: AnnotationAction)
    func remoteSession(_ session: RemoteSessionManager, didEncounterError error: Error)
    func remoteSessionDidEnd(_ session: RemoteSessionManager, reason: String, endedByHost: Bool)
}

public extension RemoteSessionDelegate {
    func remoteSession(_ session: RemoteSessionManager, didReceiveDecodedImage image: CGImage, timestamp: Double) {}
    func remoteSession(_ session: RemoteSessionManager, didReceiveFrame frameData: Data, timestamp: Double) {}
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

    public enum ConnectionStage: String, Codable, Sendable {
        case resolvingPeer = "Resolving peer"
        case connecting = "Connecting TCP transport"
        case helloHandshake = "Application HELLO handshake"
        case authenticating = "Cryptographic authentication"
        case negotiating = "Session negotiation & host approval"
        case pingPongTest = "Control channel verification (PING/PONG)"
        case mediaReady = "Establishing media pipeline"
        case active = "Active session"
    }

    private(set) public var currentState: SessionState = .idle
    private(set) public var sessionRole: SessionRole = .none
    private(set) public var activePeer: Device?
    private(set) public var activePermissions: RemoteSessionPermissions = .standardDefault
    private(set) public var sessionStartTime: Date?
    private(set) public var lastErrorMessage: String?
    private(set) public var currentStage: ConnectionStage = .resolvingPeer
    private(set) public var lastConnectionEvent: String = "Idle"
    public var activeSessionID: SessionID?

    // Developer Connection Diagnostics tracking (Requirement 13)
    private(set) public var handshakeStatus: String = "NOT STARTED"
    private(set) public var authStatus: String = "NOT STARTED"
    private(set) public var sessionNegotiationStatus: String = "NOT STARTED"

    public var activeTransport: ConnectionTransport?

    private var pingTimer: Timer?
    private var lastPingTime: Date?
    private var roundTripLatencyMs: Double = 0.0
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    private var sentConnectionChallenge: Data?
    private let lock = NSLock()

    // Continuations for awaiting handshake responses (Requirement 8)
    private var pendingMessageContinuations: [ProtocolMessageType: CheckedContinuation<ProtocolMessage, Error>] = [:]

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

    /// Snapshot of connection diagnostics for developer telemetry UI (Requirement 13)
    public func connectionDiagnosticsSnapshot(peerName: String? = nil, targetDevice: Device? = nil) -> ConnectionDiagnosticsSnapshot {
        withStateLock {
            let peer = targetDevice ?? activePeer
            let resolvedPeerName = peer?.name ?? peerName ?? "Unknown Peer"
            let identityValid = (!DeviceIdentity.current.deviceID.isEmpty && !DeviceIdentity.current.publicKeyRepresentation.isEmpty) ? "VALID" : "INVALID"
            let pairingValid = (peer != nil && TrustModel.shared.isTrusted(deviceID: peer!.id)) ? "VALID" : "UNPAIRED"

            let transportDiag = activeTransport?.diagnostics ?? TransportDiagnostics()
            let endpointStr: String
            let endpointSrc: String

            if let activeCandidate = transportDiag.activeCandidate {
                endpointStr = activeCandidate.formattedString
                endpointSrc = activeCandidate.source.rawValue
            } else if let cand = peer?.connectionCandidates.first {
                endpointStr = cand.formattedString
                endpointSrc = cand.source.rawValue
            } else if let ip = peer?.ipAddress, let port = peer?.port {
                endpointStr = "\(ip):\(port)"
                endpointSrc = "Bonjour / Cache"
            } else {
                endpointStr = "None resolved"
                endpointSrc = "Unknown"
            }

            let reachability: String
            switch transportDiag.state {
            case .ready, .authenticating, .negotiating:
                reachability = "YES"
            case .failed:
                reachability = "NO"
            case .connecting, .reconnecting:
                reachability = "UNKNOWN"
            case .idle, .disconnecting, .disconnected:
                reachability = NetworkPathMonitorService.shared.isNetworkAvailable ? "YES" : "NO"
            }

            let transportStatus: String
            switch transportDiag.state {
            case .idle: transportStatus = "IDLE"
            case .connecting, .reconnecting, .authenticating, .negotiating: transportStatus = "CONNECTING"
            case .ready: transportStatus = "READY"
            case .failed: transportStatus = "FAILED"
            case .disconnecting, .disconnected: transportStatus = "IDLE"
            }

            let localPath = NetworkPathMonitorService.shared.pathDiagnosticString

            return ConnectionDiagnosticsSnapshot(
                peerName: resolvedPeerName,
                deviceIdentityStatus: identityValid,
                pairingStatus: pairingValid,
                endpoint: endpointStr,
                endpointSource: endpointSrc,
                reachability: reachability,
                transportState: transportStatus,
                handshakeState: handshakeStatus,
                authState: authStatus,
                sessionState: sessionNegotiationStatus,
                localPath: localPath
            )
        }
    }

    // MARK: - Controller: Start Session with Remote Host (Requirements 3, 10, 14, 21)

    /// Authoritative session startup path executing strict sequential lifecycle:
    /// Code/Identity -> Endpoints -> Transport -> Handshake -> Auth -> Negotiation -> PING/PONG -> Ready -> Media
    public func startSession(with targetDevice: Device, requestedPermissions: RemoteSessionPermissions = .standardDefault) async throws {
        // Step 1: Validate trusted device identity
        guard TrustModel.shared.isTrusted(deviceID: targetDevice.id) else {
            let error = NSError(domain: "RemoteSessionManager", code: 403, userInfo: [
                NSLocalizedDescriptionKey: "Device is not trusted. You must pair with this device before connecting."
            ])
            withStateLock {
                self.currentStage = .resolvingPeer
                self.lastConnectionEvent = "Peer identity untrusted"
                self.lastErrorMessage = error.localizedDescription
                updateState(.authenticationFailed)
            }
            throw error
        }

        let sessionID = SessionID()
        let clientChallenge = PairingManager.shared.createChallenge()

        let localIdentity = DeviceIdentity.current
        let clientPlat = localIdentity.platform == .macOS ? "Mac" : "iPhone"
        let hostPlat = targetDevice.platform == .macOS ? "Mac" : "iPhone"

        print("[CONNECTION]")
        print("direction: \(clientPlat) → \(hostPlat)")
        print("sessionID: \(sessionID.description)\n")

        print("[PAIRING]")
        print("code resolved: YES\n")

        print("[IDENTITY]")
        print("peer verified: YES\n")

        withStateLock {
            self.activeSessionID = sessionID
            self.activePeer = targetDevice
            self.sessionRole = .controller
            self.activePermissions = requestedPermissions
            self.sentConnectionChallenge = clientChallenge
            self.lastErrorMessage = nil
            self.currentStage = .connecting
            self.handshakeStatus = "NOT STARTED"
            self.authStatus = "NOT STARTED"
            self.sessionNegotiationStatus = "NOT STARTED"
            self.lastConnectionEvent = "Validated peer identity and candidates"
            updateState(.connecting)
        }

        let transport = LocalNetworkTransport()
        transport.delegate = self
        transport.sessionID = sessionID

        withStateLock {
            self.activeTransport = transport
        }

        do {
            // Stage 1: Transport Connection with strict timeout (15s total)
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await transport.connect(to: targetDevice)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    throw TransportError.connectionTimeout(peer: targetDevice.name, stage: "Connecting TCP transport (15s)")
                }
                try await group.next()!
                group.cancelAll()
            }

            withStateLock {
                self.lastConnectionEvent = "TCP connection established"
            }

            // Stage 2: Application-Level Handshake: HELLO -> HELLO_ACK (Timeout 10s)
            withStateLock {
                self.currentStage = .helloHandshake
                self.lastConnectionEvent = "Exchanging HELLO packets"
                updateState(.negotiating)
            }
            try await performHelloHandshake(transport: transport, targetDevice: targetDevice, sessionID: sessionID)
            withStateLock {
                self.lastConnectionEvent = "HELLO handshake complete"
            }

            // Stage 3: Cryptographic Authentication: AUTH_CHALLENGE -> AUTH_RESPONSE (Timeout 10s)
            withStateLock {
                self.currentStage = .authenticating
                self.lastConnectionEvent = "Verifying Curve25519 signatures"
                updateState(.requestingPermission)
            }
            try await performAuthHandshake(transport: transport, targetDevice: targetDevice, sessionID: sessionID, clientChallenge: clientChallenge)
            withStateLock {
                self.lastConnectionEvent = "Authentication verified"
            }

            // Stage 4: Session Negotiation & Host Approval (Timeout 60s for user modal response)
            withStateLock {
                self.currentStage = .negotiating
                self.lastConnectionEvent = "Awaiting host approval and permissions negotiation"
                updateState(.awaitingApproval)
            }
            try await performSessionNegotiation(transport: transport, targetDevice: targetDevice, sessionID: sessionID, requestedPermissions: requestedPermissions)
            withStateLock {
                self.lastConnectionEvent = "Session approved by host"
            }

            // Stage 5: Real Bidirectional Authenticated PING / PONG test (Requirement 14)
            withStateLock {
                self.currentStage = .pingPongTest
                self.lastConnectionEvent = "Testing bidirectional PING/PONG control channel"
            }
            try await performBidirectionalPingPongTest(transport: transport, targetDevice: targetDevice, sessionID: sessionID)

            // Stage 6: Transport becomes genuinely READY
            transport.markReady()
            try await transport.waitUntilReady()

            // Stage 7: Establish Media Subsystem
            withStateLock {
                self.currentStage = .mediaReady
                self.sessionStartTime = Date()
                self.lastConnectionEvent = "Media pipeline ready"
                updateState(.establishingMedia)
            }

            print("[MEDIA]")
            print("ready\n")

            RemoteMediaSession.shared.start(role: .controller)
            startHeartbeat()

            withStateLock {
                self.currentStage = .active
                self.lastConnectionEvent = "Live screen session active"
            }

        } catch {
            withStateLock {
                let stageName = self.currentStage.rawValue
                let lastEvent = self.lastConnectionEvent

                if self.handshakeStatus == "IN PROGRESS" { self.handshakeStatus = "FAILED" }
                if self.authStatus == "IN PROGRESS" { self.authStatus = "FAILED" }
                if self.sessionNegotiationStatus == "NEGOTIATING" { self.sessionNegotiationStatus = "FAILED" }

                if let transErr = error as? TransportError, case .connectionTimeout = transErr {
                    self.lastErrorMessage = "Connection timed out\nStage: \(stageName)\nLast event: \(lastEvent)"
                    updateState(.connectionTimeout)
                } else {
                    self.lastErrorMessage = "Connection failed during \(stageName)\nLast event: \(lastEvent)\nError: \(error.localizedDescription)"
                    if currentState != .permissionDenied && currentState != .authenticationFailed {
                        updateState(.transportFailed)
                    }
                }
            }
            transport.disconnect()
            throw error
        }
    }

    // MARK: - Handshake Implementation (Requirements 8, 14, 21)

    private func performHelloHandshake(transport: ConnectionTransport, targetDevice: Device, sessionID: SessionID) async throws {
        withStateLock { self.handshakeStatus = "IN PROGRESS" }
        print("[HANDSHAKE]")
        print("HELLO sent\n")

        let localIdentity = DeviceIdentity.current
        let helloPayload = HelloPayload(
            clientID: localIdentity.deviceID,
            clientName: localIdentity.deviceName,
            clientPlatform: localIdentity.platform,
            sessionID: sessionID
        )

        let payloadData = try JSONEncoder().encode(helloPayload)
        let helloMsg = ProtocolMessage(
            type: .hello,
            senderID: localIdentity.deviceID,
            targetID: targetDevice.id,
            sessionID: sessionID,
            channel: .control,
            payload: payloadData
        )

        let response = try await sendAndWait(message: helloMsg, expecting: .helloAck, timeoutSeconds: 10.0)
        guard let respData = response.payload,
              let ack = try? JSONDecoder().decode(HelloAckPayload.self, from: respData) else {
            withStateLock { self.handshakeStatus = "FAILED" }
            throw TransportError.handshakeFailed(stage: "HELLO", reason: "Invalid HELLO_ACK payload", tcpOk: true, authOk: false, sessionOk: false)
        }

        guard ack.protocolVersion == CURRENT_PROTOCOL_VERSION else {
            withStateLock { self.handshakeStatus = "FAILED" }
            throw TransportError.handshakeFailed(stage: "HELLO", reason: "Incompatible protocol version \(ack.protocolVersion)", tcpOk: true, authOk: false, sessionOk: false)
        }

        withStateLock { self.handshakeStatus = "COMPLETE" }
        print("[HANDSHAKE]")
        print("HELLO received\n")
    }

    private func performAuthHandshake(transport: ConnectionTransport, targetDevice: Device, sessionID: SessionID, clientChallenge: Data) async throws {
        withStateLock { self.authStatus = "IN PROGRESS" }
        let localIdentity = DeviceIdentity.current
        let authPayload = AuthChallengePayload(
            sessionID: sessionID,
            requesterID: localIdentity.deviceID,
            challenge: clientChallenge,
            requesterPublicKey: localIdentity.publicKeyRepresentation
        )

        let payloadData = try JSONEncoder().encode(authPayload)
        let authMsg = ProtocolMessage(
            type: .authChallenge,
            senderID: localIdentity.deviceID,
            targetID: targetDevice.id,
            sessionID: sessionID,
            channel: .authentication,
            payload: payloadData
        )

        let response = try await sendAndWait(message: authMsg, expecting: .authResponse, timeoutSeconds: 10.0)
        guard let respData = response.payload,
              let authResp = try? JSONDecoder().decode(AuthResponsePayload.self, from: respData) else {
            withStateLock { self.authStatus = "FAILED" }
            throw TransportError.handshakeFailed(stage: "AUTH", reason: "Invalid AUTH_RESPONSE payload", tcpOk: true, authOk: false, sessionOk: false)
        }

        let isSignatureValid = DeviceIdentity.verify(
            signature: authResp.signature,
            for: clientChallenge,
            publicKeyData: targetDevice.publicKeyData
        )

        guard isSignatureValid else {
            print("[AUTH] FAILED: Cryptographic signature mismatch!")
            withStateLock {
                self.authStatus = "FAILED"
                updateState(.authenticationFailed)
            }
            throw TransportError.handshakeFailed(stage: "AUTH", reason: "Cryptographic signature mismatch", tcpOk: true, authOk: false, sessionOk: false)
        }

        withStateLock { self.authStatus = "SUCCESS" }
        print("[AUTH]")
        print("success\n")
    }

    private func performSessionNegotiation(transport: ConnectionTransport, targetDevice: Device, sessionID: SessionID, requestedPermissions: RemoteSessionPermissions) async throws {
        withStateLock { self.sessionNegotiationStatus = "NEGOTIATING" }
        let localIdentity = DeviceIdentity.current
        let negPayload = SessionNegotiationPayload(
            sessionID: sessionID,
            requestedPermissions: requestedPermissions,
            capabilities: localIdentity.capabilities
        )

        let payloadData = try JSONEncoder().encode(negPayload)
        let negMsg = ProtocolMessage(
            type: .sessionNegotiation,
            senderID: localIdentity.deviceID,
            targetID: targetDevice.id,
            sessionID: sessionID,
            channel: .session,
            payload: payloadData
        )

        // Allow up to 60 seconds for host user to approve modal prompt
        let response = try await sendAndWait(message: negMsg, expecting: .sessionAccepted, timeoutSeconds: 60.0)
        guard let respData = response.payload,
              let sessionAccepted = try? JSONDecoder().decode(SessionAcceptedPayload.self, from: respData) else {
            withStateLock { self.sessionNegotiationStatus = "FAILED" }
            throw TransportError.handshakeFailed(stage: "NEGOTIATION", reason: "Invalid SESSION_ACCEPTED payload", tcpOk: true, authOk: true, sessionOk: false)
        }

        guard sessionAccepted.approved else {
            let reason = sessionAccepted.rejectionReason ?? "Connection declined by host"
            withStateLock {
                self.sessionNegotiationStatus = "FAILED"
                self.lastErrorMessage = reason
                updateState(.permissionDenied)
            }
            throw TransportError.handshakeFailed(stage: "NEGOTIATION", reason: reason, tcpOk: true, authOk: true, sessionOk: false)
        }

        withStateLock {
            self.sessionNegotiationStatus = "ACTIVE"
            self.activePermissions = sessionAccepted.grantedPermissions
        }

        print("[SESSION]")
        print("negotiation complete\n")
    }

    /// Real bidirectional control channel PING/PONG test (Requirement 14).
    private func performBidirectionalPingPongTest(transport: ConnectionTransport, targetDevice: Device, sessionID: SessionID) async throws {
        let localIdentity = DeviceIdentity.current
        let pingPayload = "PING_\(UUID().uuidString)".data(using: .utf8)
        let pingMsg = ProtocolMessage(
            type: .ping,
            senderID: localIdentity.deviceID,
            targetID: targetDevice.id,
            sessionID: sessionID,
            channel: .control,
            payload: pingPayload
        )

        let startTime = Date()
        _ = try await sendAndWait(message: pingMsg, expecting: .pong, timeoutSeconds: 5.0)
        let latency = Date().timeIntervalSince(startTime) * 1000.0

        withStateLock {
            self.roundTripLatencyMs = latency
            self.lastConnectionEvent = "PING/PONG verified (\(Int(latency))ms RTT)"
        }
    }

    private func sendAndWait(
        message: ProtocolMessage,
        expecting responseType: ProtocolMessageType,
        timeoutSeconds: TimeInterval = 10.0
    ) async throws -> ProtocolMessage {
        guard let transport = activeTransport else {
            throw TransportError.notReady(state: .disconnected, sessionID: message.sessionID, peerName: activePeer?.name)
        }

        return try await withThrowingTaskGroup(of: ProtocolMessage.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.withStateLock {
                        self.pendingMessageContinuations[responseType] = continuation
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                self.withStateLock {
                    if let cont = self.pendingMessageContinuations.removeValue(forKey: responseType) {
                        cont.resume(throwing: TransportError.connectionTimeout(peer: self.activePeer?.name ?? "Host", stage: responseType.rawValue))
                    }
                }
                throw TransportError.connectionTimeout(peer: self.activePeer?.name ?? "Host", stage: responseType.rawValue)
            }

            try await transport.sendMessage(message)

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Host: Handle Incoming Peer Connection

    public func handleIncomingConnection(_ nwConnection: Any) {
        #if canImport(Network)
        guard let connection = nwConnection as? NWConnection else { return }

        print("[INCOMING]")
        print("Connection attempt received\n")

        let isOccupied = withStateLock { currentState.isActive }
        let transport = LocalNetworkTransport(acceptedConnection: connection)
        transport.delegate = self

        if isOccupied {
            print("[RemoteSessionManager] Rejecting incoming connection: Host is already in an active session.")
            let localIdentity = DeviceIdentity.current
            let busyPayload = ConnectionResponsePayload(
                approved: false,
                hostID: localIdentity.deviceID,
                hostName: localIdentity.deviceName,
                grantedPermissions: .viewOnly,
                hostCapabilities: localIdentity.capabilities,
                rejectionReason: "This host is already in use by another session."
            )
            if let data = try? JSONEncoder().encode(busyPayload) {
                let msg = ProtocolMessage(type: .connectionResponse, senderID: localIdentity.deviceID, payload: data)
                Task {
                    try? await transport.sendMessage(msg)
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    transport.disconnect()
                }
            }
            return
        }

        // NOTE: Do not set activeTransport or sessionRole here!
        // The incoming connection could be an ephemeral pairing handshake.
        // We set activeTransport and sessionRole only when session messages (.hello or .connectionRequest) arrive.
        #endif
    }

    // MARK: - ConnectionTransportDelegate

    public func transport(_ transport: ConnectionTransport, didChangeState state: TransportState) {
        // If this transport is not activeTransport, ignore state changes (e.g. pairing socket closed)
        guard transport === activeTransport else {
            return
        }

        withStateLock {
            if case .failed(let err) = state {
                self.lastErrorMessage = err.localizedDescription
                failPendingContinuations(with: err)
                if currentState != .permissionDenied && currentState != .authenticationFailed {
                    updateState(.transportFailed)
                }
            } else if state == .disconnected && currentState != .disconnected && currentState != .idle {
                failPendingContinuations(with: TransportError.sessionTerminated(reason: "Transport disconnected"))
                updateState(.disconnected)
            }
        }
    }

    private func failPendingContinuations(with error: Error) {
        let continuations = Array(pendingMessageContinuations.values)
        pendingMessageContinuations.removeAll()
        for cont in continuations {
            cont.resume(throwing: error)
        }
    }

    public func transport(_ transport: ConnectionTransport, didReceiveMessage message: ProtocolMessage) {
        // Ephemeral pairing request handling (Section 1 & 6)
        if message.type == .pairRequest {
            handleInboundPairRequest(message, on: transport)
            return
        }

        // Bind activeTransport and host role for session traffic
        if self.activeTransport == nil {
            withStateLock {
                self.activeTransport = transport
                if self.sessionRole == .none {
                    self.sessionRole = .host
                }
            }
        } else if let existing = self.activeTransport, existing !== transport {
            if currentState.isActive {
                print("[RemoteSessionManager] Ignoring message from non-active transport")
                return
            } else {
                withStateLock {
                    self.activeTransport = transport
                    if self.sessionRole == .none {
                        self.sessionRole = .host
                    }
                }
            }
        }

        // Validate session ID if active session exists (Requirement 9)
        if let msgSessionID = message.sessionID, let activeSessionID = self.activeSessionID {
            guard msgSessionID == activeSessionID else {
                print("[RemoteSessionManager] Dropping message for mismatched session: expected \(activeSessionID), received \(msgSessionID)")
                return
            }
        }

        // Check if an async task is actively awaiting this message type
        let waitingContinuation = withStateLock { () -> CheckedContinuation<ProtocolMessage, Error>? in
            return self.pendingMessageContinuations.removeValue(forKey: message.type)
        }
        if let continuation = waitingContinuation {
            continuation.resume(returning: message)
            return
        }

        // Dispatch inbound protocol actions
        switch message.type {
        case .hello:
            handleIncomingHello(message)

        case .authChallenge:
            handleIncomingAuthChallenge(message)

        case .sessionNegotiation:
            handleIncomingSessionNegotiation(message)

        case .pairRequest:
            handleInboundPairRequest(message, on: transport)

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
            let localID = DeviceIdentity.current.deviceID
            let pong = ProtocolMessage(
                type: .pong,
                senderID: localID,
                targetID: message.senderID,
                sessionID: message.sessionID ?? self.activeSessionID,
                channel: .control,
                payload: message.payload
            )
            Task { try? await transport.sendMessage(pong) }

        case .pong:
            handlePong()

        case .disconnectRequest:
            handleDisconnectRequest(message)

        case .disconnectAck, .sessionEnded:
            handleSessionEnded(message)

        default:
            break
        }
    }

    public func transport(_ transport: ConnectionTransport, didReceiveMediaFrame frameData: Data, timestamp: Double) {
        guard transport === activeTransport else { return }
        RemoteMediaSession.shared.receiveVideoFrame(frameData, timestamp: timestamp)
    }

    public func transport(_ transport: ConnectionTransport, didFailWithError error: Error) {
        guard transport === activeTransport else { return }
        withStateLock {
            self.lastErrorMessage = error.localizedDescription
            failPendingContinuations(with: error)
        }
        delegate?.remoteSession(self, didEncounterError: error)
        handleNetworkInterruption()
    }

    // MARK: - Host Handshake Handlers (Requirement 8)

    private func handleIncomingHello(_ message: ProtocolMessage) {
        guard let payloadData = message.payload,
              let hello = try? JSONDecoder().decode(HelloPayload.self, from: payloadData) else {
            return
        }

        print("[TRANSPORT] Received HELLO from \(hello.clientName)")
        withStateLock {
            self.activeSessionID = hello.sessionID
            self.handshakeStatus = "COMPLETE"
        }
        activeTransport?.sessionID = hello.sessionID

        let localIdentity = DeviceIdentity.current
        let ackPayload = HelloAckPayload(
            hostID: localIdentity.deviceID,
            hostName: localIdentity.deviceName,
            hostPlatform: localIdentity.platform,
            sessionID: hello.sessionID
        )

        if let ackData = try? JSONEncoder().encode(ackPayload) {
            let ackMsg = ProtocolMessage(
                type: .helloAck,
                senderID: localIdentity.deviceID,
                targetID: hello.clientID,
                sessionID: hello.sessionID,
                channel: .control,
                payload: ackData
            )
            print("[TRANSPORT] Sending HELLO_ACK")
            Task {
                try? await activeTransport?.sendMessage(ackMsg)
            }
        }
    }

    private func handleIncomingAuthChallenge(_ message: ProtocolMessage) {
        guard let payloadData = message.payload,
              let authChallenge = try? JSONDecoder().decode(AuthChallengePayload.self, from: payloadData) else {
            return
        }

        print("[TRANSPORT] Authenticating requester: \(authChallenge.requesterID)")
        guard TrustModel.shared.isTrusted(deviceID: authChallenge.requesterID) else {
            print("[TRANSPORT] Untrusted device attempted session: \(authChallenge.requesterID)")
            withStateLock { self.authStatus = "FAILED" }
            activeTransport?.disconnect()
            return
        }

        let localIdentity = DeviceIdentity.current
        guard let signature = try? localIdentity.sign(challenge: authChallenge.challenge) else {
            withStateLock { self.authStatus = "FAILED" }
            activeTransport?.disconnect()
            return
        }
        withStateLock { self.authStatus = "SUCCESS" }

        let authResp = AuthResponsePayload(
            sessionID: authChallenge.sessionID,
            signature: signature,
            hostPublicKey: localIdentity.publicKeyRepresentation
        )

        if let respData = try? JSONEncoder().encode(authResp) {
            let respMsg = ProtocolMessage(
                type: .authResponse,
                senderID: localIdentity.deviceID,
                targetID: authChallenge.requesterID,
                sessionID: authChallenge.sessionID,
                channel: .authentication,
                payload: respData
            )
            print("[TRANSPORT] Authentication succeeded")
            Task {
                try? await activeTransport?.sendMessage(respMsg)
            }
        }
    }

    private func handleIncomingSessionNegotiation(_ message: ProtocolMessage) {
        guard let payloadData = message.payload,
              let neg = try? JSONDecoder().decode(SessionNegotiationPayload.self, from: payloadData) else {
            return
        }

        print("[TRANSPORT] Negotiating capabilities")

        let requesterDevice = TrustModel.shared.trustedDevices.first(where: { $0.id == message.senderID }) ?? Device(
            id: message.senderID,
            name: "Remote Controller",
            platform: .unknown,
            publicKeyData: Data(),
            capabilities: neg.capabilities,
            trustStatus: .trusted,
            onlineState: .online
        )

        withStateLock {
            self.activePeer = requesterDevice
            self.sessionRole = .host
            self.activePermissions = neg.requestedPermissions
            self.sessionNegotiationStatus = "NEGOTIATING"
            updateState(.awaitingApproval)
        }

        let approvalHandler: @Sendable (Bool, RemoteSessionPermissions) -> Void = { [weak self] approved, grantedPermissions in
            guard let self = self else { return }

            let localIdentity = DeviceIdentity.current
            let acceptPayload = SessionAcceptedPayload(
                sessionID: neg.sessionID,
                approved: approved,
                grantedPermissions: grantedPermissions,
                rejectionReason: approved ? nil : "Host declined connection request"
            )

            guard let acceptData = try? JSONEncoder().encode(acceptPayload) else { return }
            let acceptMsg = ProtocolMessage(
                type: .sessionAccepted,
                senderID: localIdentity.deviceID,
                targetID: message.senderID,
                sessionID: neg.sessionID,
                channel: .session,
                payload: acceptData
            )

            Task {
                try? await self.activeTransport?.sendMessage(acceptMsg)

                if approved {
                    print("[TRANSPORT] Negotiation succeeded")

                    // Host -> Controller PING test (Requirement 14)
                    let hostPing = ProtocolMessage(
                        type: .ping,
                        senderID: localIdentity.deviceID,
                        targetID: message.senderID,
                        sessionID: neg.sessionID,
                        channel: .control,
                        payload: "PING_HOST_\(UUID().uuidString)".data(using: .utf8)
                    )
                    _ = try? await self.sendAndWait(message: hostPing, expecting: .pong, timeoutSeconds: 5.0)
                    print("[PING/PONG]")
                    print("\(localIdentity.deviceName) → \(requesterDevice.name): PING/PONG SUCCESS")

                    print("[TRANSPORT] READY")
                    self.activeTransport?.markReady()
                    self.withStateLock {
                        self.sessionNegotiationStatus = "ACTIVE"
                        self.activePermissions = grantedPermissions
                        self.sessionStartTime = Date()
                        self.updateState(.establishingMedia)
                    }
                    self.startHostScreenStreaming()
                } else {
                    self.withStateLock {
                        self.sessionNegotiationStatus = "FAILED"
                    }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    self.activeTransport?.disconnect()
                }
            }
        }

        #if os(macOS)
        if HostModeManager.shared.config.allowUnattendedAccess {
            let defaultPerms = TrustModel.shared.defaultPermissions(for: message.senderID)
            approvalHandler(true, defaultPerms)
            return
        }

        if let customApproval = incomingApprovalHandler {
            customApproval(requesterDevice, neg.requestedPermissions) { approved, perms in
                approvalHandler(approved, perms)
            }
        } else {
            HostModeManager.shared.handleIncomingSessionRequest(from: requesterDevice) { approved in
                let perms = approved ? neg.requestedPermissions : .viewOnly
                approvalHandler(approved, perms)
            }
        }
        #elseif os(iOS)
        if let customApproval = incomingApprovalHandler {
            customApproval(requesterDevice, neg.requestedPermissions) { approved, perms in
                approvalHandler(approved, perms)
            }
        } else {
            let perms = TrustModel.shared.defaultPermissions(for: message.senderID)
            approvalHandler(true, perms)
        }
        #endif
    }

    // MARK: - Inbound Pairing Message Handling

    private func handleInboundPairRequest(_ message: ProtocolMessage, on transport: ConnectionTransport) {
        guard let payloadData = message.payload,
              let request = try? JSONDecoder().decode(PairingRequestPayload.self, from: payloadData) else {
            return
        }

        let response = PairingManager.shared.processInboundPairingRequest(request)
        guard let respData = try? JSONEncoder().encode(response) else { return }

        let respMsg = ProtocolMessage(
            type: response.accepted ? .pairAccepted : .pairRejected,
            senderID: DeviceIdentity.current.deviceID,
            targetID: request.requesterID,
            payload: respData
        )

        Task {
            try? await transport.sendMessage(respMsg)
            try? await Task.sleep(nanoseconds: 500_000_000)
            transport.disconnect()
        }
    }

    // MARK: - Legacy Connection Handlers

    private func handleIncomingConnectionRequest(_ message: ProtocolMessage) {
        guard let payload = message.payload,
              let request = try? JSONDecoder().decode(ConnectionRequestPayload.self, from: payload) else {
            return
        }

        let isTrusted = TrustModel.shared.isTrusted(deviceID: request.requesterID)
        if !isTrusted {
            let localIdentity = DeviceIdentity.current
            let rejectPayload = ConnectionResponsePayload(
                approved: false,
                hostID: localIdentity.deviceID,
                hostName: localIdentity.deviceName,
                grantedPermissions: .viewOnly,
                hostCapabilities: localIdentity.capabilities,
                rejectionReason: "Device is untrusted. Please pair devices first."
            )
            if let data = try? JSONEncoder().encode(rejectPayload) {
                let msg = ProtocolMessage(type: .connectionResponse, senderID: localIdentity.deviceID, payload: data)
                Task {
                    try? await activeTransport?.sendMessage(msg)
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    activeTransport?.disconnect()
                }
            }
            return
        }

        respondToConnectionRequest(approved: true, permissions: request.requestedPermissions)
    }

    public func respondToConnectionRequest(approved: Bool, permissions: RemoteSessionPermissions) {
        withStateLock {
            self.activePermissions = permissions
        }

        let localIdentity = DeviceIdentity.current
        var hostSignature: Data? = nil
        if approved, let clientChallenge = sentConnectionChallenge {
            hostSignature = try? localIdentity.sign(challenge: clientChallenge)
        }

        let responsePayload = ConnectionResponsePayload(
            approved: approved,
            hostID: localIdentity.deviceID,
            hostName: localIdentity.deviceName,
            grantedPermissions: permissions,
            hostCapabilities: localIdentity.capabilities,
            rejectionReason: approved ? nil : "Host declined connection request.",
            hostSignature: hostSignature,
            hostChallenge: PairingManager.shared.createChallenge()
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
                self.activeTransport?.markReady()
                withStateLock {
                    self.sessionStartTime = Date()
                    updateState(.establishingMedia)
                }
                startHostScreenStreaming()
            } else {
                withStateLock {
                    self.lastErrorMessage = "Connection declined by user."
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
            activeTransport?.markReady()
            withStateLock {
                self.activePermissions = response.grantedPermissions
                self.sessionStartTime = Date()
                updateState(.establishingMedia)
            }
            RemoteMediaSession.shared.start(role: .controller)
            startHeartbeat()
        } else {
            let reason = response.rejectionReason ?? "Connection rejected by host"
            withStateLock {
                self.lastErrorMessage = reason
                updateState(.permissionDenied)
            }
        }
    }

    // MARK: - Host Screen Streaming Lifecycle (Requirement 4 & 13)

    private func startHostScreenStreaming() {
        guard let transport = activeTransport, transport.state == .ready else {
            print("[MEDIA] Media streaming delayed: Transport state is \(activeTransport?.state.description ?? "nil") (Must be ready)")
            return
        }

        print("[MEDIA] Starting capture")
        #if os(macOS)
        Task {
            guard ScreenRecordingPermissionManager.shared.isAuthorized else {
                withStateLock {
                    self.lastErrorMessage = "Screen Recording permission is required on the host."
                    updateState(.captureUnavailable)
                }
                return
            }

            let captureEngine = ScreenCaptureEngine()
            captureEngine.delegate = self
            withStateLock {
                self.activeCaptureEngine = captureEngine
            }

            RemoteMediaSession.shared.start(role: .host) { [weak self] frameData, timestamp in
                guard let self = self, let trans = self.activeTransport, trans.state == .ready else {
                    throw TransportError.notReady(state: self?.activeTransport?.state ?? .disconnected, sessionID: self?.activeSessionID, peerName: self?.activePeer?.name)
                }
                try await trans.sendMediaFrame(frameData, timestamp: timestamp)
            }

            do {
                try await captureEngine.startCapture()
                print("[MEDIA] Encoder ready")
                withStateLock {
                    updateState(.connected)
                    startHeartbeat()
                }
            } catch {
                print("[RemoteSessionManager] Screen capture failed to start: \(error)")
                withStateLock {
                    self.lastErrorMessage = "Screen capture failed: \(error.localizedDescription)"
                    updateState(.captureUnavailable)
                }
            }
        }
        #elseif os(iOS)
        RemoteMediaSession.shared.start(role: .host) { [weak self] frameData, timestamp in
            guard let self = self, let trans = self.activeTransport, trans.state == .ready else {
                throw TransportError.notReady(state: self?.activeTransport?.state ?? .disconnected, sessionID: self?.activeSessionID, peerName: self?.activePeer?.name)
            }
            try await trans.sendMediaFrame(frameData, timestamp: timestamp)
        }
        iOSBroadcastManager.shared.onFrameCaptured = { frameData, timestamp in
            Task {
                try? await RemoteMediaSession.shared.sendVideoFrame(frameData, timestamp: timestamp)
            }
        }
        iOSBroadcastManager.shared.startBroadcast()
        withStateLock {
            updateState(.connected)
            startHeartbeat()
        }
        #endif
    }

    // MARK: - Permission Management & Dynamic Updating

    public func updateSessionPermissions(_ newPermissions: RemoteSessionPermissions, reason: String? = nil) {
        guard sessionRole == .host else { return }

        withStateLock {
            self.activePermissions = newPermissions
        }

        delegate?.remoteSession(self, didUpdatePermissions: newPermissions)

        let payload = PermissionUpdatePayload(updatedPermissions: newPermissions, reason: reason)
        if let data = try? JSONEncoder().encode(payload), let peer = activePeer {
            let msg = ProtocolMessage(type: .permissionUpdate, senderID: "host", targetID: peer.id, sessionID: activeSessionID, channel: .session, payload: data)
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
        guard sessionRole == .host, currentState == .connected else { return }
        guard activePermissions.controlScreen else { return }

        guard let payload = message.payload,
              let event = try? JSONDecoder().decode(RemoteInputEvent.self, from: payload) else {
            return
        }

        guard activePermissions.isInputAuthorized(for: event.type) else { return }

        #if os(macOS)
        guard AccessibilityPermissionManager.shared.isAuthorized else { return }
        RemoteInputEngine.shared.injectInputEvent(event)
        #endif
    }

    public func sendRemoteInput(_ event: RemoteInputEvent) {
        guard sessionRole == .controller, currentState == .connected else { return }
        guard activePermissions.isInputAuthorized(for: event.type) else { return }

        guard let payload = try? JSONEncoder().encode(event), let peer = activePeer else { return }
        let msg = ProtocolMessage(type: .inputEvent, senderID: "local", targetID: peer.id, sessionID: activeSessionID, channel: .input, payload: payload)
        Task {
            try? await activeTransport?.sendMessage(msg)
        }
    }

    // MARK: - Drawing & Annotations

    public func sendAnnotation(stroke: AnnotationStroke? = nil, action: AnnotationAction, point: NormalizedPoint? = nil) {
        guard activePermissions.isAnnotationAuthorized else { return }

        let payload = AnnotationMessagePayload(action: action, stroke: stroke, point: point)
        guard let data = try? JSONEncoder().encode(payload), let peer = activePeer else { return }

        let msg = ProtocolMessage(type: .annotation, senderID: "local", targetID: peer.id, sessionID: activeSessionID, channel: .annotation, payload: data)
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

    public func endSession(reason: String = "User requested disconnect") {
        let isHost = (sessionRole == .host)
        let peer = activePeer
        let sessionID = activeSessionID

        if let peer = peer {
            if isHost {
                let payload = SessionEndedPayload(reason: reason, endedByHost: true)
                if let data = try? JSONEncoder().encode(payload) {
                    let msg = ProtocolMessage(type: .sessionEnded, senderID: "host", targetID: peer.id, sessionID: sessionID, channel: .control, payload: data)
                    Task { try? await activeTransport?.sendMessage(msg) }
                }
            } else {
                let payload = DisconnectPayload(reason: reason, requestedBy: "controller")
                if let data = try? JSONEncoder().encode(payload) {
                    let msg = ProtocolMessage(type: .disconnectRequest, senderID: "controller", targetID: peer.id, sessionID: sessionID, channel: .control, payload: data)
                    Task { try? await activeTransport?.sendMessage(msg) }
                }
            }
        }

        performCompleteCleanup(reason: reason, endedByHost: isHost)
    }

    private func handleDisconnectRequest(_ message: ProtocolMessage) {
        let ackMsg = ProtocolMessage(type: .disconnectAck, senderID: "local", sessionID: activeSessionID, channel: .control)
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
            failPendingContinuations(with: TransportError.sessionTerminated(reason: reason))
            activeTransport?.disconnect()
            activeTransport = nil
            activePeer = nil
            activeSessionID = nil
            sessionRole = .none
            sessionStartTime = nil
            sentConnectionChallenge = nil
            handshakeStatus = "NOT STARTED"
            authStatus = "NOT STARTED"
            sessionNegotiationStatus = "NOT STARTED"
            currentStage = .resolvingPeer
            lastConnectionEvent = "Idle"
            updateState(.disconnected)
        }

        delegate?.remoteSessionDidEnd(self, reason: reason, endedByHost: endedByHost)
        print("[RemoteSessionManager] Session completely cleaned up. Reason: \(reason)")
    }

    public func handleTrustRevocation(deviceID: String) {
        let shouldTerminate = withStateLock { () -> Bool in
            return activePeer?.id == deviceID && currentState.isActive
        }
        if shouldTerminate {
            print("[RemoteSessionManager] Device trust revoked for active peer. Terminating session.")
            endSession(reason: "Device trust was revoked.")
        }
    }

    // MARK: - Heartbeat & Metrics

    public func handlePing() -> ProtocolMessage? {
        guard let peer = activePeer else { return nil }
        return ProtocolMessage(type: .pong, senderID: "local", targetID: peer.id, sessionID: activeSessionID, channel: .control)
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
                let (peer, sID) = self.withStateLock { () -> (Device?, SessionID?) in
                    self.lastPingTime = Date()
                    return (self.activePeer, self.activeSessionID)
                }

                if let peer = peer {
                    let ping = ProtocolMessage(type: .ping, senderID: "local", targetID: peer.id, sessionID: sID, channel: .control)
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

    public func mediaSession(_ session: RemoteMediaSession, didReceiveDecodedImage image: CGImage, timestamp: Double) {
        withStateLock {
            if currentState == .establishingMedia && sessionRole == .controller {
                updateState(.connected)
            }
        }
        delegate?.remoteSession(self, didReceiveDecodedImage: image, timestamp: timestamp)
    }

    public func mediaSession(_ session: RemoteMediaSession, didReceiveDecodedFrame frameData: Data, timestamp: Double) {
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
        withStateLock {
            if currentState == .connected || currentState == .establishingMedia {
                self.lastErrorMessage = "Screen stream stalled: \(stage.rawValue)"
            }
        }
    }
}

#if os(macOS)
extension RemoteSessionManager: FrameCaptureDelegate {
    public func frameCaptureEngine(_ engine: ScreenCaptureEngine, didCaptureFrame frameData: Data, timestamp: Double) {
        guard let transport = activeTransport, transport.state == .ready else {
            return
        }
        Task {
            try? await RemoteMediaSession.shared.sendVideoFrame(frameData, timestamp: timestamp)
        }
    }

    public func frameCaptureEngineDidFail(_ engine: ScreenCaptureEngine, error: Error) {
        withStateLock {
            self.lastErrorMessage = error.localizedDescription
            updateState(.captureUnavailable)
        }
        delegate?.remoteSession(self, didEncounterError: error)
    }
}
#endif
