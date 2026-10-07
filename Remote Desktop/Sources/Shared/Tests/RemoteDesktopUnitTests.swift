import Foundation

/// Unit tests verifying DeviceIdentity cryptographic signatures and Keychain storage.
public final class RemoteDesktopUnitTests {
    public static func runAllTests() -> Bool {
        print("======== Running Remote Desktop Unit & Integration Test Suite ========")
        var passed = true

        passed = passed && testDeviceIdentity()
        passed = passed && testProtocolEncodingDecoding()
        passed = passed && testPairingManager()
        passed = passed && testCoordinateMapping()
        passed = passed && testFileTransferChunking()

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
        print("[TEST] PairingManager pairing code lifecycle...")
        let pairingCode = PairingManager.shared.generatePairingCode(expirationSeconds: 60)
        if pairingCode.count != 6 {
            print("❌ Pairing code length invalid")
            return false
        }

        let isValid = PairingManager.shared.validatePairingCode(pairingCode)
        if isValid {
            print("✅ PairingManager test passed")
            return true
        } else {
            print("❌ Pairing code validation failed")
            return false
        }
    }

    private static func testCoordinateMapping() -> Bool {
        print("[TEST] RemoteInputEngine coordinate mapping...")
        let mappedPoint = RemoteInputEngine.mapCoordinates(normalizedX: 0.5, normalizedY: 0.5, targetDisplayWidth: 1920, targetDisplayHeight: 1080)
        if mappedPoint.x == 960 && mappedPoint.y == 540 {
            print("✅ CoordinateMapping test passed")
            return true
        } else {
            print("❌ CoordinateMapping point mismatch: \(mappedPoint)")
            return false
        }
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
}
