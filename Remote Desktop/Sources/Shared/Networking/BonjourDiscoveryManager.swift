import Foundation
import Network

/// Handles Bonjour local network discovery and advertisement for Remote Desktop peers (`_remotedesktop._tcp`).
public final class BonjourDiscoveryManager: @unchecked Sendable {
    public static let serviceType = "_remotedesktop._tcp"
    public static let serviceDomain = "local."

    private var listener: NWListener?
    private var browser: NWBrowser?
    private let lock = NSLock()

    public var onPeerDiscovered: ((Device) -> Void)?
    public var onPeerLost: ((String) -> Void)?

    public init() {}

    /// Start advertising this device on the local network via Bonjour.
    public func startAdvertising(identity: DeviceIdentity, port: UInt16 = 58900) {
        lock.lock()
        defer { lock.unlock() }

        stopAdvertising()

        do {
            let parameters = NWParameters.tcp
            let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
            listener = try NWListener(using: parameters, on: nwPort)

            let txtRecord: [String: String] = [
                "id": identity.deviceID,
                "name": identity.deviceName,
                "pk": identity.publicKeyRepresentation.base64EncodedString()
            ]

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

    /// Stop browsing for devices.
    public func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    private func handleDiscoveredPeer(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return }

        var deviceID = name
        var publicKeyData = Data()

        if case .bonjour(let txtRecord) = result.metadata {
            if let id = txtRecord["id"] { deviceID = id }
            if let pkString = txtRecord["pk"], let data = Data(base64Encoded: pkString) {
                publicKeyData = data
            }
        }

        let device = Device(
            id: deviceID,
            name: name,
            platform: .macOS,
            publicKeyData: publicKeyData,
            trustStatus: TrustModel.shared.isTrusted(deviceID: deviceID) ? .trusted : .untrusted,
            onlineState: .online,
            lastSeen: Date()
        )

        onPeerDiscovered?(device)
    }

    private func handleLostPeer(_ result: NWBrowser.Result) {
        if case .service(let name, _, _, _) = result.endpoint {
            onPeerLost?(name)
        }
    }
}
