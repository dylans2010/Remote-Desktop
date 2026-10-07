import Foundation

/// Unit and integration tests verifying DeviceIdentity, ProtocolEngine, Permissions, SessionState, Annotations, and Diagnostics.
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
        // Test Host perspective: frames captured = 0 -> capture issue
        let hostCaptureIssue = MediaHealthMetrics(framesCaptured: 0, framesEncoded: 0, framesSent: 0)
        guard hostCaptureIssue.diagnosePipeline(isHost: true) == .capture else {
            print("❌ Expected capture diagnosis for zero captured frames")
            return false
        }

        // Test Host perspective: captured > 0, encoded = 0 -> encoding issue
        let hostEncodeIssue = MediaHealthMetrics(framesCaptured: 10, framesEncoded: 0, framesSent: 0)
        guard hostEncodeIssue.diagnosePipeline(isHost: true) == .encoding else {
            print("❌ Expected encoding diagnosis")
            return false
        }

        // Test Controller perspective: frames received = 0 -> reception issue
        let controllerReceptionIssue = MediaHealthMetrics(framesReceived: 0, framesDecoded: 0, framesRendered: 0)
        guard controllerReceptionIssue.diagnosePipeline(isHost: false) == .reception else {
            print("❌ Expected reception diagnosis for zero received frames")
            return false
        }

        // Test Controller perspective: frames received > 0, rendered = 0 -> rendering issue
        let controllerRenderIssue = MediaHealthMetrics(framesReceived: 100, framesDecoded: 100, framesRendered: 0)
        guard controllerRenderIssue.diagnosePipeline(isHost: false) == .rendering else {
            print("❌ Expected rendering diagnosis")
            return false
        }

        // Test healthy pipeline
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
}
