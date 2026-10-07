import Foundation
import Network

/// Handles Bonjour local network discovery and advertisement for Remote Desktop peers (`_remotedesktop._tcp`).
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

    public init() {}

    /// Start advertising this device on the local network via Bonjour.
    public func startAdvertising(identity: DeviceIdentity, port: UInt16 = 58900) {
        lock.lock()
        defer { lock.unlock() }

        self.currentIdentity = identity
        self.currentPort = port

        stopAdvertising()

        do {
            let parameters = NWParameters.tcp
            let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
            listener = try NWListener(using: parameters, on: nwPort)

            var txtRecord: [String: String] = [
                "id": identity.deviceID,
                "name": identity.deviceName,
                "platform": identity.platform.rawValue,
                "port": String(port),
                "pk": identity.publicKeyRepresentation.base64EncodedString(),
                "pairing": isPairingActive ? "1" : "0"
            ]
            if let ph = currentPairHash {
                txtRecord["pairHash"] = ph
            }

            listener?.service = NWListener.Service(
                name: identity.deviceName,
                type: BonjourDiscoveryManager.serviceType,
                domain: BonjourDiscoveryManager.serviceDomain,
                txtRecord: NWTXTRecord(txtRecord)
            )

            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[Bonjour] Advertising successfully on port \(port)")
                case .failed(let error):
                    print("[Bonjour] Listener failed with error: \(error)")
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { newConnection in
                print("[Bonjour] Incoming connection received on listener")
                RemoteSessionManager.shared.handleIncomingConnection(newConnection)
            }

            listener?.start(queue: .global(qos: .userInitiated))
        } catch {
            print("[Bonjour] Failed to initialize NWListener: \(error)")
        }
    }

    /// Stop advertising local device.
    public func stopAdvertising() {
        listener?.cancel()
        listener = nil
    }

    /// Dynamically update pairing TXT record without interrupting existing connections.
    public func updatePairingAdvertisement(active: Bool, pairHash: String?) {
        lock.lock()
        self.isPairingActive = active
        self.currentPairHash = pairHash
        let identity = self.currentIdentity ?? DeviceIdentity.current
        let port = self.currentPort
        lock.unlock()

        startAdvertising(identity: identity, port: port)
    }

    /// Start browsing for other Remote Desktop devices on the local LAN.
    public func startBrowsing() {
        lock.lock()
        defer { lock.unlock() }

        stopBrowsing()

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

    /// Start browsing for other Remote Desktop devices on the local LAN with a callback returning current devices.
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
        browser?.cancel()
        browser = nil
    }

    private func handleDiscoveredPeer(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return }

        var deviceID = name
        var publicKeyData = Data()
        var discoveredPlatform = DevicePlatform.macOS
        var peerPort: UInt16? = 58900
        var ipAddress: String? = nil

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
        }

        // Endpoint host resolution or service host
        if case .service(let serviceName, let type, let domain, _) = result.endpoint {
            ipAddress = "\(serviceName).\(type).\(domain)"
        }

        let device = Device(
            id: deviceID,
            name: name,
            platform: discoveredPlatform,
            publicKeyData: publicKeyData,
            trustStatus: TrustModel.shared.isTrusted(deviceID: deviceID) ? .trusted : .untrusted,
            onlineState: .online,
            lastSeen: Date(),
            ipAddress: ipAddress,
            port: peerPort
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
