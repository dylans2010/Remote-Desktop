import Foundation
import Network

/// Telemetry and monitoring service observing the system's local NWPath network route.
/// Strictly diagnostic: NWPath.status == .satisfied only confirms local routing exists,
/// not that a remote peer is reachable.
public final class NetworkPathMonitorService: @unchecked Sendable {
    public static let shared = NetworkPathMonitorService()

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.remotedesktop.pathmonitor", qos: .utility)
    private let lock = NSLock()

    public private(set) var currentStatus: NWPath.Status = .requiresConnection
    public private(set) var isExpensive: Bool = false
    public private(set) var isConstrained: Bool = false
    public private(set) var activeInterfaceNames: [String] = []

    public var onPathChanged: ((NWPath) -> Void)?

    private init() {
        self.monitor = NWPathMonitor()
        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.lock.lock()
            self.currentStatus = path.status
            self.isExpensive = path.isExpensive
            self.isConstrained = path.isConstrained

            var interfaces: [String] = []
            if path.usesInterfaceType(.wifi) { interfaces.append("Wi-Fi") }
            if path.usesInterfaceType(.cellular) { interfaces.append("Cellular") }
            if path.usesInterfaceType(.wiredEthernet) { interfaces.append("Ethernet") }
            if interfaces.isEmpty { interfaces.append("Other") }
            self.activeInterfaceNames = interfaces
            self.lock.unlock()

            // Trigger network interface cache refresh
            NetworkInterfaceManager.shared.refreshInterfaces()
            self.onPathChanged?(path)
        }
        self.monitor.start(queue: self.queue)
    }

    public var isNetworkAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentStatus == .satisfied
    }

    /// Diagnostic summary string formatted for connection attempt logging.
    public var pathDiagnosticString: String {
        lock.lock()
        defer { lock.unlock() }

        let statusStr: String
        switch currentStatus {
        case .satisfied: statusStr = "satisfied"
        case .unsatisfied: statusStr = "unsatisfied"
        case .requiresConnection: statusStr = "requiresConnection"
        @unknown default: statusStr = "unknown"
        }

        let ifList = activeInterfaceNames.joined(separator: ", ")
        return "\(statusStr) (Interfaces: [\(ifList)], expensive: \(isExpensive), constrained: \(isConstrained))"
    }
}
