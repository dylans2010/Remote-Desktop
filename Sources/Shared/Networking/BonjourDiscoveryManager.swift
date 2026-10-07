import Foundation
import Network

/// Handles Bonjour local network discovery and advertisement for Remote Desktop peers (`_remotedesktop._tcp`).
/// Authoritative host listener lifecycle and candidate endpoint publisher.
public final class BonjourDiscoveryManager: @unchecked Sendable {
    public static let serviceType = "_remotedesktop._tcp"
    public static let serviceDomain = "local."

    private var listener: NWListener?
    private var browser: NWBrowser?
    private let lock = NSLock()

    public static let shared = BonjourDiscoveryManager()
    private var discoveredPeersMap: [String: Device] = [:]

    public var onPeerDiscovered: ((Device) -> Void)?
    public var onPeerLost: ((String) -> Void)?

    public func currentDiscoveredDevices() -> [Device] {
        lock.lock()
        defer { lock.unlock() }
        return Array(discoveredPeersMap.values)
    }

    private var currentIdentity: DeviceIdentity?
    private var currentPort: UInt16 = 58900
    private var isPairingActive: Bool = false
    private var currentPairHash: String?

    public init() {
        // Automatically refresh network advertisements when local network interface or path changes
        NetworkPathMonitorService.shared.onPathChanged = { [weak self] _ in
            self?.refreshAdvertisementIfActive()
        }
    }

    // MARK: - Server Listener Lifecycle (Requirements 5, 6, 7, 16)

    /// Start advertising this device on the local network via Bonjour and start the TCP host listener.
    public func startAdvertising(identity: DeviceIdentity, port: UInt16 = 58900) {
        lock.lock()
        self.currentIdentity = identity
        self.currentPort = port

        // If listener is already active on this port and healthy, update service dynamically without restart
        if let existing = listener, existing.state == .ready {
            let service = buildBonjourService(identity: identity, port: port)
            existing.service = service
            lock.unlock()
            return
        }

        stopAdvertisingInternal()

        print("[SERVER]")
        print("Creating listener\n")

        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableFastOpen = false
            tcpOptions.noDelay = true

            let parameters = NWParameters(tls: nil, tcp: tcpOptions)
            parameters.allowLocalEndpointReuse = true
            parameters.includePeerToPeer = true

            let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
            let newListener = try NWListener(using: parameters, on: nwPort)

            newListener.service = buildBonjourService(identity: identity, port: port)

            newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                guard let self = self else { return }
                switch state {
                case .setup:
                    break
                case .waiting(let error):
                    print("[SERVER]")
                    print("FAILED")
                    print("reason: Waiting - \(error.localizedDescription)\n")
                case .ready:
                    let activePort = newListener?.port?.rawValue ?? port
                    self.lock.lock()
                    self.currentPort = activePort
                    self.lock.unlock()

                    print("[SERVER]")
                    print("Listener starting\n")
                    print("[SERVER]")
                    print("Listening\n")
                    print("[SERVER]")
                    print("Port: \(activePort)\n")
                    print("[SERVER]")
                    print("Waiting for connections\n")

                case .failed(let error):
                    print("[SERVER]")
                    print("FAILED")
                    print("reason: \(error.localizedDescription)\n")

                case .cancelled:
                    break
                @unknown default:
                    break
                }
            }

            newListener.newConnectionHandler = { newConnection in
                let remoteEndpoint = newConnection.endpoint.debugDescription
                print("[INCOMING]")
                print("Connection received from \(remoteEndpoint)\n")
                RemoteSessionManager.shared.handleIncomingConnection(newConnection)
            }

            self.listener = newListener
            lock.unlock()

            newListener.start(queue: .global(qos: .userInitiated))
        } catch {
            lock.unlock()
            print("[SERVER]")
            print("FAILED")
            print("reason: \(error.localizedDescription)\n")
        }
    }

    private func buildBonjourService(identity: DeviceIdentity, port: UInt16) -> NWListener.Service {
        // Collect real local LAN IP addresses (Requirement 7: Never advertise localhost/127.0.0.1/::1)
        let localLANIPs = NetworkInterfaceManager.shared.currentLocalLANAddresses()
        let ipString = localLANIPs.prefix(4).joined(separator: ",")

        var txtRecord: [String: String] = [
            "id": identity.deviceID,
            "name": identity.deviceName,
            "platform": identity.platform.rawValue,
            "port": String(port),
            "pk": identity.publicKeyRepresentation.base64EncodedString(),
            "pairing": isPairingActive ? "1" : "0",
            "ips": ipString
        ]
        if let ph = currentPairHash {
            txtRecord["pairHash"] = ph
        }

        return NWListener.Service(
            name: identity.deviceName,
            type: BonjourDiscoveryManager.serviceType,
            domain: BonjourDiscoveryManager.serviceDomain,
            txtRecord: NWTXTRecord(txtRecord)
        )
    }

    private func refreshAdvertisementIfActive() {
        lock.lock()
        guard let identity = currentIdentity else {
            lock.unlock()
            return
        }
        let port = currentPort
        lock.unlock()

        startAdvertising(identity: identity, port: port)
    }

    /// Stop advertising local device and close listener.
    public func stopAdvertising() {
        lock.lock()
        defer { lock.unlock() }
        stopAdvertisingInternal()
    }

    private func stopAdvertisingInternal() {
        listener?.cancel()
        listener = nil
    }

    /// Dynamically update pairing TXT record without interrupting existing listener socket.
    public func updatePairingAdvertisement(active: Bool, pairHash: String?) {
        lock.lock()
        self.isPairingActive = active
        self.currentPairHash = pairHash
        let identity = self.currentIdentity ?? DeviceIdentity.current
        let port = self.currentPort

        if let existing = listener, existing.state == .ready {
            let service = buildBonjourService(identity: identity, port: port)
            existing.service = service
            lock.unlock()
            return
        }
        lock.unlock()

        startAdvertising(identity: identity, port: port)
    }

    // MARK: - Client Browsing Lifecycle

    /// Start browsing for other Remote Desktop devices on the local LAN.
    public func startBrowsing() {
        lock.lock()
        defer { lock.unlock() }

        stopBrowsingInternal()

        let descriptor = NWBrowser.Descriptor.bonjour(type: BonjourDiscoveryManager.serviceType, domain: BonjourDiscoveryManager.serviceDomain)
        let parameters = NWParameters.tcp
        browser = NWBrowser(for: descriptor, using: parameters)

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            for change in changes {
                switch change {
                case .added(let result):
                    self.handleDiscoveredPeer(result)
                case .removed(let result):
                    self.handleLostPeer(result)
                default:
                    break
                }
            }
        }

        browser?.start(queue: .global(qos: .userInitiated))
    }

    /// Start browsing with a notification callback.
    public func startBrowsing(onChange: @escaping ([Device]) -> Void) {
        onPeerDiscovered = { [weak self] _ in
            guard let self = self else { return }
            let devices = self.lock.withLock { Array(self.discoveredPeersMap.values) }
            onChange(devices)
        }
        onPeerLost = { [weak self] _ in
            guard let self = self else { return }
            let devices = self.lock.withLock { Array(self.discoveredPeersMap.values) }
            onChange(devices)
        }
        startBrowsing()
    }

    /// Stop browsing for devices.
    public func stopBrowsing() {
        lock.lock()
        defer { lock.unlock() }
        stopBrowsingInternal()
    }

    private func stopBrowsingInternal() {
        browser?.cancel()
        browser = nil
    }

    // MARK: - Peer Discovery & Endpoint Candidate Resolution (Requirements 1, 2, 15)

    private func handleDiscoveredPeer(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return }

        var deviceID = name
        var publicKeyData = Data()
        var discoveredPlatform = DevicePlatform.macOS
        var peerPort: UInt16 = 58900
        var advertisedIPs: [String] = []

        if case .bonjour(let txtRecord) = result.metadata {
            if let id = txtRecord["id"] { deviceID = id }
            if let pkString = txtRecord["pk"], let data = Data(base64Encoded: pkString) {
                publicKeyData = data
            }
            if let platStr = txtRecord["platform"], let parsedPlat = DevicePlatform(rawValue: platStr) {
                discoveredPlatform = parsedPlat
            }
            if let portStr = txtRecord["port"], let parsedPort = UInt16(portStr) {
                peerPort = parsedPort
            }
            if let ips = txtRecord["ips"], !ips.isEmpty {
                advertisedIPs = ips.components(separatedBy: ",").filter { !$0.isEmpty }
            }
        }

        // Build priority-ordered connection candidates (Requirements 1, 2, 15)
        var candidates: [ConnectionCandidate] = []

        // 1. Direct LAN IP candidates (highest priority: 10)
        for ip in advertisedIPs {
            let isV6 = ip.contains(":")
            let transportKind: TransportKind = isV6 ? .lanIPv6 : .lanIPv4
            let candidate = ConnectionCandidate(
                transport: transportKind,
                host: ip,
                port: peerPort,
                priority: 10,
                expiresAt: Date().addingTimeInterval(300),
                source: .bonjour,
                interface: nil,
                isIPv6: isV6
            )
            if !candidates.contains(where: { $0.host == ip && $0.port == peerPort }) {
                candidates.append(candidate)
            }
        }

        // 2. Bonjour Service candidate (priority: 5)
        let bonjourCandidate = ConnectionCandidate(
            transport: .bonjourService,
            host: name,
            port: peerPort,
            priority: 5,
            expiresAt: Date().addingTimeInterval(300),
            source: .bonjour,
            interface: nil,
            isIPv6: false
        )
        candidates.append(bonjourCandidate)

        // Select best available primary IP address (direct LAN IP preferred over service name)
        let primaryIP = advertisedIPs.first

        let device = Device(
            id: deviceID,
            name: name,
            platform: discoveredPlatform,
            publicKeyData: publicKeyData,
            trustStatus: TrustModel.shared.isTrusted(deviceID: deviceID) ? .trusted : .untrusted,
            onlineState: .online,
            lastSeen: Date(),
            ipAddress: primaryIP,
            port: peerPort,
            connectionCandidates: candidates
        )

        lock.lock()
        discoveredPeersMap[deviceID] = device
        lock.unlock()

        onPeerDiscovered?(device)
    }

    private func handleLostPeer(_ result: NWBrowser.Result) {
        if case .service(let name, _, _, _) = result.endpoint {
            lock.lock()
            discoveredPeersMap.removeValue(forKey: name)
            lock.unlock()
            onPeerLost?(name)
        }
    }
}
