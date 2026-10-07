import Foundation
import CryptoKit

/// Single pairing session code with timestamp and expiration window.
public struct PairingCode: Codable, Sendable {
    public let code: String
    public let createdAt: Date
    public let expiresIn: TimeInterval // default 300s (5 minutes)

    public var isExpired: Bool {
        return Date().timeIntervalSince(createdAt) > expiresIn
    }
}

/// Generates and validates short-lived secure pairing codes and verifies peer authentication.
public final class PairingManager: @unchecked Sendable {
    public static let shared = PairingManager()

    private var currentActiveCode: PairingCode?
    private let lock = NSLock()

    private init() {}

    /// Generate a short-lived 6-digit numeric pairing code.
    public func generatePairingCode(expirationSeconds: TimeInterval = 300) -> String {
        lock.lock()
        defer { lock.unlock() }

        let randomNum = Int.random(in: 100000...999999)
        let codeString = String(randomNum)
        currentActiveCode = PairingCode(code: codeString, createdAt: Date(), expiresIn: expirationSeconds)
        return codeString
    }

    /// Get currently active unexpired pairing code if present.
    public var activeCode: String? {
        lock.lock()
        defer { lock.unlock() }

        guard let active = currentActiveCode, !active.isExpired else {
            currentActiveCode = nil
            return nil
        }
        return active.code
    }

    /// Validate a candidate pairing code submitted by a peer.
    public func validatePairingCode(_ candidateCode: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let active = currentActiveCode else { return false }
        if active.isExpired {
            currentActiveCode = nil
            return false
        }

        let isValid = (active.code == candidateCode.trimmingCharacters(in: .whitespacesAndNewlines))
        if isValid {
            // Pairing code is single-use: invalidate upon successful match
            currentActiveCode = nil
        }
        return isValid
    }

    /// Create cryptographic challenge payload for mutual authentication.
    public func createChallenge() -> Data {
        var randomBytes = Data(count: 32)
        _ = randomBytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        return randomBytes
    }

    /// Verify response signature against challenge and peer public key.
    public func verifyChallengeResponse(signature: Data, challenge: Data, peerPublicKeyData: Data) -> Bool {
        return DeviceIdentity.verify(signature: signature, for: challenge, publicKeyData: peerPublicKeyData)
    }
}
