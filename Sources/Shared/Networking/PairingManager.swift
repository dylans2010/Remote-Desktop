import Foundation
import CryptoKit
import Network

/// Strongly-typed pairing errors according to system architecture.
public enum PairingError: LocalizedError, Sendable, Equatable {
    case invalidCode
    case expiredCode
    case alreadyUsed
    case deviceUnavailable
    case authenticationFailed
    case pairingRejected(reason: String)
    case rateLimited
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "Invalid pairing code"
        case .expiredCode:
            return "Pairing code expired"
        case .alreadyUsed:
            return "Pairing code has already been used"
        case .deviceUnavailable:
            return "Device unavailable or unreachable"
        case .authenticationFailed:
            return "Cryptographic authentication failed"
        case .pairingRejected(let reason):
            return "Pairing rejected: \(reason)"
        case .rateLimited:
            return "Too many failed attempts. Please wait before trying again."
        case .networkError(let msg):
            return "Network connection failed: \(msg)"
        }
    }
}

/// Single pairing session code with timestamp, expiration window, and replay protection.
public struct PairingCode: Codable, Sendable {
    public let code: String
    public let createdAt: Date
    public let expiresIn: TimeInterval // default 300s (5 minutes)
    public let deviceID: String
    public var isUsed: Bool

    public init(code: String, createdAt: Date = Date(), expiresIn: TimeInterval = 300, deviceID: String, isUsed: Bool = false) {
        self.code = code
        self.createdAt = createdAt
        self.expiresIn = expiresIn
        self.deviceID = deviceID
        self.isUsed = isUsed
    }

    public var isExpired: Bool {
        return Date().timeIntervalSince(createdAt) > expiresIn
    }

    /// Derive a truncated SHA256 pairing fingerprint for network advertisement.
    public var fingerprint: String {
        let combined = "\(code):\(deviceID)"
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// Generates and validates short-lived secure pairing codes and verifies peer authentication.
public final class PairingManager: @unchecked Sendable {
    public static let shared = PairingManager()

    private var currentActiveCode: PairingCode?
    private var failedAttempts: Int = 0
    private var lastFailedAttemptTime: Date?
    private let lock = NSLock()

    private init() {}

    /// Generate a short-lived 6-digit numeric pairing code and advertise temporary pairing endpoint.
    @discardableResult
    public func generatePairingCode(expirationSeconds: TimeInterval = 300) -> String {
        lock.lock()
        defer { lock.unlock() }

        let randomNum = Int.random(in: 100000...999999)
        let codeString = String(randomNum)
        let localDeviceID = DeviceIdentity.current.deviceID
        let pairingCode = PairingCode(
            code: codeString,
            createdAt: Date(),
            expiresIn: expirationSeconds,
            deviceID: localDeviceID,
            isUsed: false
        )
        currentActiveCode = pairingCode

        // Update Bonjour advertisement with pairing state and code fingerprint
        BonjourDiscoveryManager.shared.updatePairingAdvertisement(active: true, pairHash: pairingCode.fingerprint)

        print("[PAIRING] Generated pairing code for device \(localDeviceID) (expires in \(Int(expirationSeconds))s)")
        return codeString
    }

    /// Invalidate active pairing code (e.g. after successful pair or dismissal).
    public func invalidateActiveCode() {
        lock.lock()
        defer { lock.unlock() }
        currentActiveCode = nil
        BonjourDiscoveryManager.shared.updatePairingAdvertisement(active: false, pairHash: nil)
    }

    /// Get currently active unexpired pairing code if present.
    public var activeCode: String? {
        lock.lock()
        defer { lock.unlock() }

        guard let active = currentActiveCode, !active.isExpired, !active.isUsed else {
            currentActiveCode = nil
            return nil
        }
        return active.code
    }

    /// Validate a candidate pairing code submitted by a peer locally (e.g. when checking code on host).
    public func validatePairingCode(_ candidateCode: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let trimmed = candidateCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let active = currentActiveCode, !active.isExpired, !active.isUsed else {
            return false
        }
        return active.code == trimmed
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

    // MARK: - Inbound Pairing Request Processing (Host Side)

    /// Process an inbound pairing request from a remote peer entering our pairing code.
    public func processInboundPairingRequest(_ payload: PairingRequestPayload) -> PairingResponsePayload {
        lock.lock()
        defer { lock.unlock() }

        // 1. Rate limiting check (max 5 failed attempts within 60s)
        if let lastFail = lastFailedAttemptTime, Date().timeIntervalSince(lastFail) < 60, failedAttempts >= 5 {
            print("[PAIRING] Inbound pairing rejected: Rate limited.")
            return PairingResponsePayload(accepted: false, rejectionReason: "Too many failed attempts. Rate limited.")
        }

        // 2. Validate active code state
        guard let active = currentActiveCode else {
            recordFailedAttempt()
            print("[PAIRING] Inbound pairing rejected: No active pairing code.")
            return PairingResponsePayload(accepted: false, rejectionReason: "Invalid pairing code")
        }

        if active.isExpired {
            currentActiveCode = nil
            print("[PAIRING] Inbound pairing rejected: Pairing code expired.")
            return PairingResponsePayload(accepted: false, rejectionReason: "Pairing code expired")
        }

        if active.isUsed {
            currentActiveCode = nil
            print("[PAIRING] Inbound pairing rejected: Pairing code already used.")
            return PairingResponsePayload(accepted: false, rejectionReason: "Pairing code has already been used")
        }

        // 3. Verify entered 6-digit code matches
        let trimmedCandidate = payload.candidateCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard active.code == trimmedCandidate else {
            recordFailedAttempt()
            print("[PAIRING] Inbound pairing rejected: Code mismatch.")
            return PairingResponsePayload(accepted: false, rejectionReason: "Invalid pairing code")
        }

        // 4. Cryptographic challenge response: Host signs requester's challenge
        let localIdentity = DeviceIdentity.current
        guard let hostSignature = try? localIdentity.sign(challenge: payload.requesterChallenge) else {
            print("[PAIRING] Inbound pairing failed: Unable to sign challenge.")
            return PairingResponsePayload(accepted: false, rejectionReason: "Authentication failure on host")
        }

        // 5. Generate host challenge for mutual authentication
        let hostChallenge = createChallenge()

        // 6. Consume pairing code (one-time use replay protection)
        currentActiveCode?.isUsed = true
        currentActiveCode = nil
        failedAttempts = 0
        BonjourDiscoveryManager.shared.updatePairingAdvertisement(active: false, pairHash: nil)

        // 7. Register requester as trusted device in local TrustModel
        let requesterDevice = Device(
            id: payload.requesterID,
            name: payload.requesterName,
            platform: payload.requesterPlatform,
            publicKeyData: payload.requesterPublicKey,
            capabilities: payload.requesterCapabilities,
            trustStatus: .trusted,
            onlineState: .online
        )
        TrustModel.shared.trustDevice(requesterDevice)

        print("[PAIRING]")
        print("Code accepted\n")

        print("[PAIRING]")
        print("Resolved device:")
        print("  deviceID: \(payload.requesterID)")
        print("  platform: \(payload.requesterPlatform.rawValue)")
        print("  displayName: \(payload.requesterName)\n")

        print("[PAIRING] Inbound pairing succeeded! Paired with \(payload.requesterName) (\(payload.requesterID))")

        return PairingResponsePayload(
            accepted: true,
            rejectionReason: nil,
            hostID: localIdentity.deviceID,
            hostName: localIdentity.deviceName,
            hostPlatform: localIdentity.platform,
            hostPublicKey: localIdentity.publicKeyRepresentation,
            hostSignature: hostSignature,
            hostChallenge: hostChallenge,
            hostCapabilities: localIdentity.capabilities
        )
    }

    private func recordFailedAttempt() {
        failedAttempts += 1
        lastFailedAttemptTime = Date()
    }

    // MARK: - Outbound Pairing Handshake (Client Side) (Requirements 1, 2, 9)

    /// Pair with remote peer device given an entered numeric code with cryptographic challenge-response.
    public func pairWithDevice(using code: String) async throws -> Device {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        // Enforce valid 6-digit numeric structure
        guard trimmed.count == 6 && trimmed.allSatisfy({ $0.isNumber }) else {
            throw PairingError.invalidCode
        }

        // 1. Resolve reachable devices on local network with brief discovery wait if needed
        var discovered = BonjourDiscoveryManager.shared.currentDiscoveredDevices()
        if discovered.isEmpty {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            discovered = BonjourDiscoveryManager.shared.currentDiscoveredDevices()
        }

        if discovered.isEmpty {
            print("[PAIRING] No candidate devices discovered on local network.")
            throw PairingError.networkError("No devices discovered on local network. Ensure both devices are on the same Wi-Fi with Local Network permission granted.")
        }

        print("[PAIRING] Attempting pairing code resolution against \(discovered.count) discovered device(s)...")

        // 2. Try pairing with reachable candidate devices
        var lastError: PairingError = .invalidCode
        for candidate in discovered {
            do {
                let pairedDevice = try await performPairingHandshake(with: candidate, candidateCode: trimmed)
                return pairedDevice
            } catch let error as PairingError {
                lastError = error
                if error == .invalidCode || error == .expiredCode || error == .alreadyUsed {
                    lastError = error
                }
            } catch {
                lastError = .networkError(error.localizedDescription)
            }
        }

        throw lastError
    }

    /// Legacy completion-handler wrapper for pairWithDevice.
    public func pairWithDevice(using code: String, completion: @escaping @Sendable (Bool, Device?, Error?) -> Void) {
        Task {
            do {
                let device = try await pairWithDevice(using: code)
                completion(true, device, nil)
            } catch {
                completion(false, nil, error)
            }
        }
    }

    /// Execute the end-to-end cryptographic challenge-response pairing exchange over network transport.
    private func performPairingHandshake(with peer: Device, candidateCode: String) async throws -> Device {
        // Collect viable candidate endpoints
        var candidateEndpoints = peer.connectionCandidates

        if candidateEndpoints.isEmpty {
            if let ip = peer.ipAddress, !ip.isEmpty {
                let isV6 = ip.contains(":")
                candidateEndpoints.append(ConnectionCandidate(
                    transport: isV6 ? .lanIPv6 : .lanIPv4,
                    host: ip,
                    port: peer.port ?? 58900,
                    priority: 10,
                    source: .cached,
                    isIPv6: isV6
                ))
            }
            candidateEndpoints.append(ConnectionCandidate(
                transport: .bonjourService,
                host: peer.name,
                port: peer.port ?? 58900,
                priority: 5,
                source: .bonjour
            ))
        }

        // Rule 7: Never advertise or connect to localhost / 127.0.0.1 / ::1
        candidateEndpoints.removeAll { c in
            let h = c.host
            return h == "127.0.0.1" || h == "localhost" || h == "::1" || h.hasPrefix("127.")
        }

        candidateEndpoints.sort { $0.priority > $1.priority }

        guard !candidateEndpoints.isEmpty else {
            throw PairingError.deviceUnavailable
        }

        var lastHandshakeError: Error = PairingError.deviceUnavailable

        // Try candidate endpoints in priority order
        for candidate in candidateEndpoints {
            let endpoint = candidate.toNWEndpoint()
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableFastOpen = false
            tcpOptions.noDelay = true

            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.includePeerToPeer = true
            let nwConn = NWConnection(to: endpoint, using: params)

            do {
                // Connect with strict 5-second timeout
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            nwConn.stateUpdateHandler = { state in
                                switch state {
                                case .ready:
                                    continuation.resume()
                                case .failed(let err):
                                    continuation.resume(throwing: err)
                                case .cancelled:
                                    continuation.resume(throwing: PairingError.deviceUnavailable)
                                default:
                                    break
                                }
                            }
                            nwConn.start(queue: .global(qos: .userInitiated))
                        }
                    }

                    group.addTask {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        throw PairingError.networkError("Connection to \(candidate.host):\(candidate.port) timed out")
                    }

                    try await group.next()!
                    group.cancelAll()
                }

                defer {
                    nwConn.cancel()
                }

                // Prepare PairingRequestPayload with cryptographic challenge
                let localIdentity = DeviceIdentity.current
                let requesterChallenge = createChallenge()
                let requestPayload = PairingRequestPayload(
                    candidateCode: candidateCode,
                    requesterID: localIdentity.deviceID,
                    requesterName: localIdentity.deviceName,
                    requesterPlatform: localIdentity.platform,
                    requesterPublicKey: localIdentity.publicKeyRepresentation,
                    requesterChallenge: requesterChallenge,
                    requesterCapabilities: localIdentity.capabilities
                )

                let payloadData = try JSONEncoder().encode(requestPayload)
                let pairMessage = ProtocolMessage(
                    type: .pairRequest,
                    senderID: localIdentity.deviceID,
                    targetID: peer.id,
                    payload: payloadData
                )

                // Send pair request packet (0x01 tag)
                let msgData = try ProtocolEngine.encode(pairMessage)
                let packetPayloadLength = 1 + msgData.count
                var lengthBigEndian = UInt32(packetPayloadLength).bigEndian
                var packetData = Data(bytes: &lengthBigEndian, count: 4)
                packetData.append(0x01) // control packet tag
                packetData.append(msgData)

                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    nwConn.send(content: packetData, completion: .contentProcessed { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    })
                }

                // Receive response packet from host
                let responseMsg = try await receiveProtocolMessage(from: nwConn)

                guard let responsePayloadData = responseMsg.payload,
                      let response = try? JSONDecoder().decode(PairingResponsePayload.self, from: responsePayloadData) else {
                    throw PairingError.invalidCode
                }

                guard response.accepted else {
                    let reason = response.rejectionReason ?? "Invalid pairing code"
                    if reason.localizedCaseInsensitiveContains("expired") {
                        throw PairingError.expiredCode
                    } else if reason.localizedCaseInsensitiveContains("already used") {
                        throw PairingError.alreadyUsed
                    } else if reason.localizedCaseInsensitiveContains("rate limited") {
                        throw PairingError.rateLimited
                    } else {
                        throw PairingError.invalidCode
                    }
                }

                guard let hostID = response.hostID,
                      let hostName = response.hostName,
                      let hostPublicKey = response.hostPublicKey,
                      let hostSignature = response.hostSignature,
                      let hostChallenge = response.hostChallenge else {
                    throw PairingError.authenticationFailed
                }

                // Cryptographic verification: Verify Host's signature for our challenge
                let isHostAuthentic = DeviceIdentity.verify(
                    signature: hostSignature,
                    for: requesterChallenge,
                    publicKeyData: hostPublicKey
                )

                guard isHostAuthentic else {
                    print("[PAIRING] Cryptographic verification failed! Host signature invalid.")
                    throw PairingError.authenticationFailed
                }

                // Mutual authentication: Sign Host's challenge and return confirmation
                guard let clientSignature = try? localIdentity.sign(challenge: hostChallenge) else {
                    throw PairingError.authenticationFailed
                }

                let confirmPayload = PairingConfirmPayload(
                    requesterID: localIdentity.deviceID,
                    requesterSignature: clientSignature
                )
                if let confirmData = try? JSONEncoder().encode(confirmPayload) {
                    let confirmMsg = ProtocolMessage(
                        type: .pairAccepted,
                        senderID: localIdentity.deviceID,
                        targetID: hostID,
                        payload: confirmData
                    )
                    if let encConfirm = try? ProtocolEngine.encode(confirmMsg) {
                        let confLen = 1 + encConfirm.count
                        var confLenBigEndian = UInt32(confLen).bigEndian
                        var confPacket = Data(bytes: &confLenBigEndian, count: 4)
                        confPacket.append(0x01)
                        confPacket.append(encConfirm)
                        nwConn.send(content: confPacket, completion: .contentProcessed { _ in })
                    }
                }

                // Log resolved peer and endpoints conforming to Requirement 2
                print("[PAIRING]")
                print("Code accepted\n")

                let hostPlat = response.hostPlatform ?? peer.platform
                print("[PAIRING]")
                print("Resolved device:")
                print("  deviceID: \(hostID)")
                print("  platform: \(hostPlat.rawValue)")
                print("  displayName: \(hostName)\n")

                print("[PAIRING]")
                print("Resolved endpoints:")
                for cand in candidateEndpoints {
                    print(cand.logDescription)
                }
                print("")

                // Create verified TrustedDevice and save to Keychain
                let trustedDevice = Device(
                    id: hostID,
                    name: hostName,
                    platform: hostPlat,
                    publicKeyData: hostPublicKey,
                    capabilities: response.hostCapabilities ?? .macOSDefault,
                    trustStatus: .trusted,
                    onlineState: .online,
                    ipAddress: candidate.transport != .bonjourService ? candidate.host : peer.ipAddress,
                    port: candidate.port,
                    connectionCandidates: candidateEndpoints
                )

                TrustModel.shared.trustDevice(trustedDevice)
                print("[PAIRING] Outbound pairing succeeded with authentic host: \(hostName) (\(hostID))")
                return trustedDevice

            } catch {
                lastHandshakeError = error
                nwConn.cancel()
                if let pairErr = error as? PairingError, pairErr == .invalidCode || pairErr == .expiredCode || pairErr == .alreadyUsed {
                    throw pairErr
                }
            }
        }

        if let pairErr = lastHandshakeError as? PairingError {
            throw pairErr
        } else {
            throw PairingError.networkError(lastHandshakeError.localizedDescription)
        }
    }

    private func receiveProtocolMessage(from connection: NWConnection) async throws -> ProtocolMessage {
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 4, maximumLength: 65536) { content, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data = content, data.count >= 5 else {
                    continuation.resume(throwing: PairingError.networkError("Malformed response"))
                    return
                }

                let payloadLength = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let packetBytes = data.dropFirst(4)
                guard packetBytes.count >= payloadLength else {
                    continuation.resume(throwing: PairingError.networkError("Incomplete packet"))
                    return
                }

                let tag = packetBytes.first
                guard tag == 0x01 else {
                    continuation.resume(throwing: PairingError.networkError("Invalid packet tag"))
                    return
                }

                let msgData = packetBytes.dropFirst()
                do {
                    let msg = try ProtocolEngine.decode(Data(msgData))
                    continuation.resume(returning: msg)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
