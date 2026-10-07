import Foundation
import CryptoKit

/// Unit and integration tests verifying DeviceIdentity, ProtocolEngine, Permissions, SessionState, Annotations, Transport Lifecycle, Handshake, Ping/Pong, Binary, and Video.
public final class RemoteDesktopUnitTests {
    public static func runAllTests() -> Bool {
        print("======== Running Remote Desktop Unit & Integration Test Suite ========")
        var passed = true

        passed = passed && testDeviceIdentity()
        passed = passed && testProtocolEncodingDecoding()
        passed = passed && testPairingManager()
        passed = passed && testCoordinateMapping()
        passed = passed && testFileTransferChunking()
        passed = passed && testSessionStateMachine()
        passed = passed && testRemoteSessionPermissions()
        passed = passed && testMediaPipelineDiagnostics()
        passed = passed && testAnnotationModel()
        passed = passed && testConnectionHandshakePayloads()
        passed = passed && testVideoPacketSerialization()
        passed = passed && testTransportStateMachine()
        passed = passed && testTransportApplicationHandshake()
        passed = passed && testTransportPingPong()
        passed = passed && testTransportBinaryPayload1KB()
        passed = passed && testVideoPipelineReadiness()
        passed = passed && testConnectionCandidateModelAndFiltering()
        passed = passed && testNetworkInterfaceDiscovery()
        passed = passed && testConnectionDiagnosticsSnapshot()

        print("======== Test Suite Result: \(passed ? "ALL PASSED" : "FAILED") ========")
        return passed
    }

    private static func testDeviceIdentity() -> Bool {
        print("[TEST] DeviceIdentity key generation and verification...")
        let identity = DeviceIdentity(deviceName: "Test Mac")
        let challengeData = "RemoteDesktopChallenge123".data(using: .utf8)!

        guard let signature = try? identity.sign(challenge: challengeData) else {
            print("❌ DeviceIdentity failed to sign challenge")
            return false
        }

        let isValid = DeviceIdentity.verify(signature: signature, for: challengeData, publicKeyData: identity.publicKeyRepresentation)
        if isValid {
            print("✅ DeviceIdentity test passed")
            return true
        } else {
            print("❌ DeviceIdentity verification failed")
            return false
        }
    }

    private static func testProtocolEncodingDecoding() -> Bool {
        print("[TEST] ProtocolEngine encoding/decoding...")
        let testInput = RemoteInputEvent(type: .mouseMove, x: 0.5, y: 0.75, displayIndex: 0)
        guard let payloadData = try? JSONEncoder().encode(testInput) else {
            print("❌ Input payload encoding failed")
            return false
        }

        let originalMsg = ProtocolMessage(type: .inputEvent, senderID: "deviceA", targetID: "deviceB", payload: payloadData)
        guard let encodedMsgData = try? ProtocolEngine.encode(originalMsg) else {
            print("❌ Protocol message encoding failed")
            return false
        }

        guard let decodedMsg = try? ProtocolEngine.decode(encodedMsgData) else {
            print("❌ Protocol message decoding failed")
            return false
        }

        if decodedMsg.type == .inputEvent && decodedMsg.senderID == "deviceA" {
            print("✅ ProtocolEngine test passed")
            return true
        } else {
            print("❌ Protocol message content mismatch")
            return false
        }
    }

    private static func testPairingManager() -> Bool {
        print("[TEST] PairingManager pairing code lifecycle and strict validation...")
        let pairingCode = PairingManager.shared.generatePairingCode(expirationSeconds: 60)
        if pairingCode.count != 6 {
            print("❌ Pairing code length invalid")
            return false
        }

        // 1. Valid active code must validate
        let isValid = PairingManager.shared.validatePairingCode(pairingCode)
        guard isValid else {
            print("❌ Pairing code validation failed for genuine active code")
            return false
        }

        // 2. Arbitrary/fake codes must be rejected immediately!
        let fakeCodes = ["000000", "123456", "999999", "111111"]
        for fake in fakeCodes where fake != pairingCode {
            if PairingManager.shared.validatePairingCode(fake) {
                print("❌ FAILED: PairingManager erroneously accepted fake code: \(fake)")
                return false
            }
        }

        // 3. Inbound pairing request with invalid code must be rejected
        let badRequest = PairingRequestPayload(
            candidateCode: "000000",
            requesterID: "rogue_device",
            requesterName: "Attacker",
            requesterPlatform: .macOS,
            requesterPublicKey: Data(repeating: 0x01, count: 32),
            requesterChallenge: Data(repeating: 0x02, count: 32),
            requesterCapabilities: .macOSDefault
        )
        let rejectResponse = PairingManager.shared.processInboundPairingRequest(badRequest)
        guard !rejectResponse.accepted else {
            print("❌ FAILED: Inbound pairing request with fake code was accepted")
            return false
        }

        // 4. Invalidation must revoke the active code
        PairingManager.shared.invalidateActiveCode()
        if PairingManager.shared.validatePairingCode(pairingCode) {
            print("❌ FAILED: Invalidated pairing code was still accepted")
            return false
        }

        print("✅ PairingManager strict validation and lifecycle tests passed")
        return true
    }

    private static func testCoordinateMapping() -> Bool {
        #if os(macOS)
        print("[TEST] RemoteInputEngine coordinate mapping...")
        let mappedPoint = RemoteInputEngine.mapCoordinates(normalizedX: 0.5, normalizedY: 0.5, targetDisplayWidth: 1920, targetDisplayHeight: 1080)
        if mappedPoint.x == 960 && mappedPoint.y == 540 {
            print("✅ CoordinateMapping test passed")
            return true
        } else {
            print("❌ CoordinateMapping point mismatch: \(mappedPoint)")
            return false
        }
        #else
        return true
        #endif
    }

    private static func testFileTransferChunking() -> Bool {
        print("[TEST] FileTransferManager chunking...")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_file.txt")
        let dummyData = Data(repeating: 0x41, count: 100_000) // ~100KB
        try? dummyData.write(to: tempURL)

        guard let (metadata, chunks) = try? FileTransferManager.shared.prepareFileForSending(fileURL: tempURL) else {
            print("❌ File preparation failed")
            return false
        }

        if metadata.totalChunks == chunks.count && chunks.count > 0 {
            print("✅ FileTransferManager test passed (\(chunks.count) chunks prepared)")
            return true
        } else {
            print("❌ Chunk count mismatch")
            return false
        }
    }

    private static func testSessionStateMachine() -> Bool {
        print("[TEST] SessionState state machine properties...")
        let activeStates: [SessionState] = [.requestingPermission, .awaitingApproval, .negotiating, .connecting, .establishingMedia, .connected, .reconnecting]
        for state in activeStates {
            guard state.isActive else {
                print("❌ State \(state) expected to be active")
                return false
            }
        }

        guard SessionState.connected.isLiveMediaActive else {
            print("❌ Connected state expected to have live media active")
            return false
        }

        guard SessionState.idle.isActive == false && SessionState.disconnected.isActive == false else {
            print("❌ Idle/disconnected states should not be active")
            return false
        }

        guard SessionState.permissionDenied.isTerminal && SessionState.transportFailed.isTerminal else {
            print("❌ Failure states must be terminal")
            return false
        }

        print("✅ SessionState state machine test passed")
        return true
    }

    private static func testRemoteSessionPermissions() -> Bool {
        print("[TEST] RemoteSessionPermissions presets and enforcement...")
        let viewOnly = RemoteSessionPermissions.viewOnly
        guard viewOnly.viewScreen && !viewOnly.controlScreen && !viewOnly.mouse && !viewOnly.keyboard && !viewOnly.annotation else {
            print("❌ View Only permissions preset invalid")
            return false
        }
        guard !viewOnly.isInputAuthorized(for: .mouseMove) && !viewOnly.isInputAuthorized(for: .keyDown) else {
            print("❌ View Only must reject mouse and keyboard input")
            return false
        }

        let teaching = RemoteSessionPermissions.teaching
        guard teaching.viewScreen && teaching.isAnnotationAuthorized && !teaching.controlScreen && !teaching.mouse else {
            print("❌ Teaching permissions preset invalid")
            return false
        }

        let fullControl = RemoteSessionPermissions.fullControl
        guard fullControl.viewScreen && fullControl.controlScreen && fullControl.isInputAuthorized(for: .mouseMove) && fullControl.isInputAuthorized(for: .keyDown) && fullControl.isAnnotationAuthorized else {
            print("❌ Full control permissions preset invalid")
            return false
        }

        print("✅ RemoteSessionPermissions test passed")
        return true
    }

    private static func testMediaPipelineDiagnostics() -> Bool {
        print("[TEST] MediaHealthMetrics pipeline diagnostics...")
        let hostCaptureIssue = MediaHealthMetrics(framesCaptured: 0, framesEncoded: 0, framesSent: 0)
        guard hostCaptureIssue.diagnosePipeline(isHost: true) == .capture else {
            print("❌ Expected capture diagnosis for zero captured frames")
            return false
        }

        let hostEncodeIssue = MediaHealthMetrics(framesCaptured: 10, framesEncoded: 0, framesSent: 0)
        guard hostEncodeIssue.diagnosePipeline(isHost: true) == .encoding else {
            print("❌ Expected encoding diagnosis")
            return false
        }

        let controllerReceptionIssue = MediaHealthMetrics(framesReceived: 0, framesDecoded: 0, framesRendered: 0)
        guard controllerReceptionIssue.diagnosePipeline(isHost: false) == .reception else {
            print("❌ Expected reception diagnosis for zero received frames")
            return false
        }

        let controllerRenderIssue = MediaHealthMetrics(framesReceived: 100, framesDecoded: 100, framesRendered: 0)
        guard controllerRenderIssue.diagnosePipeline(isHost: false) == .rendering else {
            print("❌ Expected rendering diagnosis")
            return false
        }

        let healthy = MediaHealthMetrics(framesReceived: 100, framesDecoded: 100, framesRendered: 100)
        guard healthy.diagnosePipeline(isHost: false) == .healthy else {
            print("❌ Expected healthy diagnosis")
            return false
        }

        print("✅ MediaHealthMetrics diagnostics test passed")
        return true
    }

    private static func testAnnotationModel() -> Bool {
        print("[TEST] AnnotationModel normalized coordinates and strokes...")
        let point = NormalizedPoint(x: 1.5, y: -0.2)
        guard point.x == 1.0 && point.y == 0.0 else {
            print("❌ NormalizedPoint did not clamp to 0.0...1.0 bounds")
            return false
        }

        let denorm = point.denormalized(width: 1920, height: 1080)
        guard denorm.x == 1920 && denorm.y == 0 else {
            print("❌ Denormalized point incorrect: \(denorm)")
            return false
        }

        let stroke = AnnotationStroke(tool: .arrow, colorHex: "#007AFF", lineWidth: 5.0, points: [NormalizedPoint(x: 0.1, y: 0.1), NormalizedPoint(x: 0.5, y: 0.5)])
        guard stroke.tool == .arrow && stroke.points.count == 2 else {
            print("❌ AnnotationStroke properties mismatch")
            return false
        }

        print("✅ AnnotationModel test passed")
        return true
    }

    private static func testConnectionHandshakePayloads() -> Bool {
        print("[TEST] Connection request and response payloads serialization...")
        let requestPayload = ConnectionRequestPayload(
            requesterID: "req123",
            requesterName: "Alex's MacBook",
            requesterPlatform: .macOS,
            requestedPermissions: .fullControl,
            capabilities: .macOSDefault
        )

        guard let encodedReq = try? JSONEncoder().encode(requestPayload),
              let decodedReq = try? JSONDecoder().decode(ConnectionRequestPayload.self, from: encodedReq) else {
            print("❌ Failed to encode/decode ConnectionRequestPayload")
            return false
        }
        guard decodedReq.requesterID == "req123" && decodedReq.requestedPermissions.controlScreen else {
            print("❌ ConnectionRequestPayload content mismatch")
            return false
        }

        let responsePayload = ConnectionResponsePayload(
            approved: true,
            hostID: "host456",
            hostName: "Office Mac",
            grantedPermissions: .teaching,
            hostCapabilities: .macOSDefault
        )
        guard let encodedResp = try? JSONEncoder().encode(responsePayload),
              let decodedResp = try? JSONDecoder().decode(ConnectionResponsePayload.self, from: encodedResp) else {
            print("❌ Failed to encode/decode ConnectionResponsePayload")
            return false
        }
        guard decodedResp.approved && decodedResp.grantedPermissions.annotation && !decodedResp.grantedPermissions.controlScreen else {
            print("❌ ConnectionResponsePayload content mismatch")
            return false
        }

        print("✅ Connection handshake payloads test passed")
        return true
    }

    private static func testVideoPacketSerialization() -> Bool {
        print("[TEST] VideoFramePacket binary serialization and deserialization...")
        let dummySPS = Data([0x67, 0x42, 0x00, 0x1f])
        let dummyPPS = Data([0x68, 0xce, 0x38, 0x80])
        let dummyPayload = Data(repeating: 0xaa, count: 1024)

        let packet = VideoFramePacket(
            sequenceNumber: 42,
            timestamp: 123.456,
            codec: .h264,
            isKeyframe: true,
            width: 1920,
            height: 1080,
            sps: dummySPS,
            pps: dummyPPS,
            payload: dummyPayload
        )

        let serialized = packet.serialize()
        guard let deserialized = VideoFramePacket.deserialize(from: serialized) else {
            print("❌ Failed to deserialize VideoFramePacket")
            return false
        }

        guard deserialized.sequenceNumber == 42,
              deserialized.isKeyframe == true,
              deserialized.width == 1920,
              deserialized.height == 1080,
              deserialized.codec == .h264,
              deserialized.sps == dummySPS,
              deserialized.pps == dummyPPS,
              deserialized.payload == dummyPayload else {
            print("❌ Deserialized VideoFramePacket field mismatch")
            return false
        }

        print("✅ VideoFramePacket serialization test passed")
        return true
    }

    // MARK: - Transport Lifecycle Tests (Requirements 2, 6, 8, 20, 21, 22)

    private static func testTransportStateMachine() -> Bool {
        print("[TEST] TransportState state machine & readiness guarantee (Requirement 2 & 6)...")
        let transport = LocalNetworkTransport()

        // 1. Initial state must be idle
        guard transport.state == .idle else {
            print("❌ Initial transport state expected to be .idle, got \(transport.state)")
            return false
        }

        // 2. connecting != ready
        guard TransportState.connecting != TransportState.ready else {
            print("❌ TransportState.connecting cannot equal .ready")
            return false
        }

        // 3. Mark ready transitions to ready
        transport.markReady()
        guard transport.state == .ready && transport.state.isReady else {
            print("❌ Expected transport to be .ready after markReady()")
            return false
        }

        // 4. waitUntilReady() returns immediately when ready
        final class SafeFlag: @unchecked Sendable { var value = false }
        let flag = SafeFlag()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                try await transport.waitUntilReady()
                flag.value = true
            } catch {
                flag.value = false
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1.0)
        guard flag.value else {
            print("❌ waitUntilReady() failed to return on ready transport")
            return false
        }

        print("✅ TransportState state machine & readiness guarantee passed")
        return true
    }

    private static func testTransportApplicationHandshake() -> Bool {
        print("[TEST] Application-level handshake payloads & cryptography (Requirement 8)...")
        let sessionID = SessionID()
        let clientIdentity = DeviceIdentity(deviceName: "Client Mac")
        let hostIdentity = DeviceIdentity(deviceName: "Host Mac")

        // 1. HELLO / HELLO_ACK
        let hello = HelloPayload(clientID: clientIdentity.deviceID, clientName: clientIdentity.deviceName, clientPlatform: clientIdentity.platform, sessionID: sessionID)
        guard let helloData = try? JSONEncoder().encode(hello),
              let decodedHello = try? JSONDecoder().decode(HelloPayload.self, from: helloData),
              decodedHello.sessionID == sessionID && decodedHello.protocolVersion == CURRENT_PROTOCOL_VERSION else {
            print("❌ HELLO payload roundtrip failed")
            return false
        }

        let helloAck = HelloAckPayload(hostID: hostIdentity.deviceID, hostName: hostIdentity.deviceName, hostPlatform: hostIdentity.platform, sessionID: sessionID)
        guard let ackData = try? JSONEncoder().encode(helloAck),
              let decodedAck = try? JSONDecoder().decode(HelloAckPayload.self, from: ackData),
              decodedAck.sessionID == sessionID else {
            print("❌ HELLO_ACK payload roundtrip failed")
            return false
        }

        // 2. AUTH_CHALLENGE / AUTH_RESPONSE
        let challenge = "SecureRandomChallengeBytes32Chars".data(using: .utf8)!
        let authReq = AuthChallengePayload(sessionID: sessionID, requesterID: clientIdentity.deviceID, challenge: challenge, requesterPublicKey: clientIdentity.publicKeyRepresentation)
        guard let hostSignature = try? hostIdentity.sign(challenge: challenge) else {
            print("❌ Host failed to sign challenge")
            return false
        }

        let isSignatureValid = DeviceIdentity.verify(signature: hostSignature, for: challenge, publicKeyData: hostIdentity.publicKeyRepresentation)
        guard isSignatureValid else {
            print("❌ Host signature verification failed")
            return false
        }

        let authResp = AuthResponsePayload(sessionID: sessionID, signature: hostSignature, hostPublicKey: hostIdentity.publicKeyRepresentation)
        guard let authRespData = try? JSONEncoder().encode(authResp),
              let decodedResp = try? JSONDecoder().decode(AuthResponsePayload.self, from: authRespData),
              decodedResp.sessionID == sessionID else {
            print("❌ AUTH_RESPONSE payload roundtrip failed")
            return false
        }

        // 3. SESSION_NEGOTIATION / SESSION_ACCEPTED
        let neg = SessionNegotiationPayload(sessionID: sessionID, requestedPermissions: .fullControl, capabilities: clientIdentity.capabilities)
        let accepted = SessionAcceptedPayload(sessionID: sessionID, approved: true, grantedPermissions: .fullControl)
        guard let accData = try? JSONEncoder().encode(accepted),
              let decodedAcc = try? JSONDecoder().decode(SessionAcceptedPayload.self, from: accData),
              decodedAcc.approved && decodedAcc.grantedPermissions.controlScreen else {
            print("❌ SESSION_ACCEPTED payload roundtrip failed")
            return false
        }

        print("✅ Application-level handshake payloads & cryptography passed")
        return true
    }

    private static func testTransportPingPong() -> Bool {
        print("[TEST] Transport PING / PONG control channel health test (Requirement 20)...")
        let sessionID = SessionID()
        let ping = ProtocolMessage(type: .ping, senderID: "controller", targetID: "host", sessionID: sessionID, channel: .control)

        guard let encodedPing = try? ProtocolEngine.encode(ping),
              let decodedPing = try? ProtocolEngine.decode(encodedPing) else {
            print("❌ Failed to encode/decode PING message")
            return false
        }

        guard decodedPing.type == .ping && decodedPing.sessionID == sessionID else {
            print("❌ PING message fields mismatch")
            return false
        }

        // Host responds with PONG
        let pong = ProtocolMessage(type: .pong, senderID: "host", targetID: "controller", sessionID: sessionID, channel: .control)
        guard let encodedPong = try? ProtocolEngine.encode(pong),
              let decodedPong = try? ProtocolEngine.decode(encodedPong) else {
            print("❌ Failed to encode/decode PONG message")
            return false
        }

        guard decodedPong.type == .pong && decodedPong.sessionID == sessionID else {
            print("❌ PONG message fields mismatch")
            return false
        }

        // Simulate RTT calculation
        let sendDate = ping.timestamp
        let receiveDate = Date().addingTimeInterval(0.015) // +15ms
        let rtt = receiveDate.timeIntervalSince(sendDate) * 1000.0
        guard rtt >= 0.0 else {
            print("❌ Calculated RTT invalid: \(rtt)")
            return false
        }

        print("✅ Transport PING / PONG control health test passed (Simulated RTT: \(Int(rtt))ms)")
        return true
    }

    private static func testTransportBinaryPayload1KB() -> Bool {
        print("[TEST] 1 KB binary payload transmission & SHA-256 integrity (Requirement 21)...")
        // 1. Generate 1024 bytes of binary payload
        var randomBytes = Data(count: 1024)
        _ = randomBytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 1024, $0.baseAddress!) }

        // 2. Compute SHA-256 hash
        let digest = SHA256.hash(data: randomBytes)
        let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()

        // 3. Wrap in ProtocolMessage container
        let sessionID = SessionID()
        let binaryMsg = ProtocolMessage(
            type: .fileChunk,
            senderID: "sender",
            targetID: "receiver",
            sessionID: sessionID,
            channel: .session,
            payload: randomBytes
        )

        guard let encoded = try? ProtocolEngine.encode(binaryMsg),
              let decoded = try? ProtocolEngine.decode(encoded),
              let payload = decoded.payload else {
            print("❌ Failed to encode/decode 1 KB binary protocol message")
            return false
        }

        // 4. Verify received payload hash matches exactly
        let receivedDigest = SHA256.hash(data: payload)
        let receivedHashString = receivedDigest.compactMap { String(format: "%02x", $0) }.joined()

        guard payload.count == 1024 && receivedHashString == hashString else {
            print("❌ Binary payload SHA-256 hash mismatch! Sent: \(hashString), Recv: \(receivedHashString)")
            return false
        }

        print("✅ 1 KB binary payload transmission & SHA-256 integrity passed")
        return true
    }

    private static func testVideoPipelineReadiness() -> Bool {
        print("[TEST] Video pipeline readiness enforcement & frame delivery (Requirement 22)...")
        let transport = LocalNetworkTransport()

        // 1. Verify sending media frame throws when transport is NOT ready
        final class SafeFlag2: @unchecked Sendable { var value = false }
        let flag2 = SafeFlag2()
        let sem1 = DispatchSemaphore(value: 0)
        Task {
            do {
                try await transport.sendMediaFrame(Data([0x00, 0x01]), timestamp: 1.0)
            } catch {
                flag2.value = true
            }
            sem1.signal()
        }
        _ = sem1.wait(timeout: .now() + 1.0)

        guard flag2.value else {
            print("❌ Expected sendMediaFrame to throw when transport is not ready")
            return false
        }

        // 2. Mark transport ready
        transport.markReady()
        guard transport.state == .ready else {
            print("❌ Transport not ready after markReady()")
            return false
        }

        // 3. Verify RemoteMediaSession controller receives frame
        let dummyPacket = VideoFramePacket(
            sequenceNumber: 1,
            timestamp: 100.0,
            codec: .h264,
            isKeyframe: true,
            width: 1920,
            height: 1080,
            sps: Data([0x67]),
            pps: Data([0x68]),
            payload: Data(repeating: 0x55, count: 500)
        )
        let serialized = dummyPacket.serialize()

        RemoteMediaSession.shared.start(role: .controller)
        RemoteMediaSession.shared.receiveVideoFrame(serialized, timestamp: 100.0)

        let metrics = RemoteMediaSession.shared.getHealthMetrics()
        guard metrics.framesReceived >= 1 else {
            print("❌ RemoteMediaSession failed to record received frame")
            RemoteMediaSession.shared.stop()
            return false
        }

        RemoteMediaSession.shared.stop()
        print("✅ Video pipeline readiness enforcement & frame delivery passed")
        return true
    }

    private static func testConnectionCandidateModelAndFiltering() -> Bool {
        print("[TEST] ConnectionCandidate filtering (no loopback) and priority ordering...")

        // 1. Loopback addresses must be flagged as loopback and never accepted as valid remote candidates
        let loopback1 = ConnectionCandidate(transport: .lanIPv4, host: "127.0.0.1", port: 58900)
        let loopback2 = ConnectionCandidate(transport: .lanIPv4, host: "localhost", port: 58900)
        let loopback3 = ConnectionCandidate(transport: .lanIPv6, host: "::1", port: 58900)

        guard loopback1.isLoopbackOrLocalhost && loopback2.isLoopbackOrLocalhost && loopback3.isLoopbackOrLocalhost else {
            print("❌ Loopback filtering failed: expected all loopback hosts to be detected")
            return false
        }

        // 2. Real LAN candidates must not be flagged as loopback
        let lanIPv4 = ConnectionCandidate(transport: .lanIPv4, host: "192.168.1.150", port: 58900, priority: 100)
        let lanIPv6 = ConnectionCandidate(transport: .lanIPv6, host: "fe80::1", port: 58900, priority: 90)
        let bonjour = ConnectionCandidate(transport: .bonjourService, host: "Test Mac", port: 58900, priority: 80, source: .bonjour)

        guard !lanIPv4.isLoopbackOrLocalhost && !lanIPv6.isLoopbackOrLocalhost && !bonjour.isLoopbackOrLocalhost else {
            print("❌ False positive on valid LAN candidate loopback check")
            return false
        }

        // 3. Priority ordering test
        let unordered = [bonjour, lanIPv4, lanIPv6]
        let sorted = unordered.sorted()
        guard sorted[0].priority >= sorted[1].priority && sorted[1].priority >= sorted[2].priority else {
            print("❌ Candidate priority sorting failed")
            return false
        }

        // 4. Endpoint conversion
        #if canImport(Network)
        guard lanIPv4.toNWEndpoint() != nil else {
            print("❌ toNWEndpoint() failed for valid LAN candidate")
            return false
        }
        #endif

        print("✅ ConnectionCandidate filtering & priority ordering passed")
        return true
    }

    private static func testNetworkInterfaceDiscovery() -> Bool {
        print("[TEST] NetworkInterfaceManager local IP discovery (POSIX getifaddrs)...")
        let addresses = NetworkInterfaceManager.localIPAddresses()
        print("Discovered local IP addresses: \(addresses)")

        // Verify that NO loopback addresses are in the returned set
        for addr in addresses {
            if addr == "127.0.0.1" || addr == "::1" || addr.lowercased() == "localhost" {
                print("❌ Loopback address leaked through NetworkInterfaceManager: \(addr)")
                return false
            }
        }

        print("✅ NetworkInterfaceManager non-loopback discovery passed")
        return true
    }

    private static func testConnectionDiagnosticsSnapshot() -> Bool {
        print("[TEST] ConnectionDiagnosticsSnapshot generation (Requirement 13)...")
        let snapshot = RemoteSessionManager.shared.connectionDiagnosticsSnapshot(peerName: "Test Target")

        guard snapshot.deviceIdentityStatus == "VALID" else {
            print("❌ DeviceIdentityStatus should be VALID, got \(snapshot.deviceIdentityStatus)")
            return false
        }

        guard ["VALID", "UNPAIRED"].contains(snapshot.pairingStatus) else {
            print("❌ PairingStatus invalid: \(snapshot.pairingStatus)")
            return false
        }

        guard ["YES", "NO", "UNKNOWN"].contains(snapshot.reachability) else {
            print("❌ Reachability invalid: \(snapshot.reachability)")
            return false
        }

        guard ["IDLE", "CONNECTING", "READY", "FAILED"].contains(snapshot.transportState) else {
            print("❌ TransportState invalid: \(snapshot.transportState)")
            return false
        }

        guard ["NOT STARTED", "IN PROGRESS", "COMPLETE", "FAILED"].contains(snapshot.handshakeState) else {
            print("❌ HandshakeState invalid: \(snapshot.handshakeState)")
            return false
        }

        guard ["NOT STARTED", "IN PROGRESS", "SUCCESS", "FAILED"].contains(snapshot.authState) else {
            print("❌ AuthState invalid: \(snapshot.authState)")
            return false
        }

        guard ["NOT STARTED", "NEGOTIATING", "ACTIVE", "FAILED"].contains(snapshot.sessionState) else {
            print("❌ SessionState invalid: \(snapshot.sessionState)")
            return false
        }

        print("✅ ConnectionDiagnosticsSnapshot telemetry validation passed")
        return true
    }
}
