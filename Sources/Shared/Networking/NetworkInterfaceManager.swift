import Foundation
import Network

/// Represents an active network interface discovered on the local machine.
public struct NetworkInterfaceInfo: Codable, Sendable, Identifiable {
    public var id: String { "\(name)_\(address)" }
    public let name: String
    public let address: String
    public let isIPv6: Bool
    public let isLAN: Bool
    public let isLoopback: Bool

    public init(name: String, address: String, isIPv6: Bool, isLAN: Bool, isLoopback: Bool = false) {
        self.name = name
        self.address = address
        self.isIPv6 = isIPv6
        self.isLAN = isLAN
        self.isLoopback = isLoopback
    }
}

/// Discovers active local IPv4 and IPv6 network interfaces using POSIX getifaddrs.
/// Strictly filters out loopback and non-routable interfaces for remote advertisements.
public final class NetworkInterfaceManager: @unchecked Sendable {
    public static let shared = NetworkInterfaceManager()

    private let lock = NSLock()
    private var cachedInterfaces: [NetworkInterfaceInfo] = []
    private var lastRefreshTime: Date = .distantPast

    private init() {
        refreshInterfaces()
    }

    /// Retrieve all active network interfaces excluding loopback.
    public func getActiveInterfaces(forceRefresh: Bool = false) -> [NetworkInterfaceInfo] {
        lock.lock()
        defer { lock.unlock() }

        if forceRefresh || Date().timeIntervalSince(lastRefreshTime) > 10.0 {
            refreshInternal()
        }
        return cachedInterfaces
    }

    /// Retrieve only non-loopback private LAN IP addresses (IPv4 & IPv6).
    public func currentLocalLANAddresses() -> [String] {
        return getActiveInterfaces().filter { $0.isLAN && !$0.isLoopback }.map { $0.address }
    }

    /// Static convenience accessor for discovered local non-loopback IP addresses.
    public static func localIPAddresses() -> [String] {
        return shared.currentLocalLANAddresses()
    }

    /// Refresh cached interfaces list.
    public func refreshInterfaces() {
        lock.lock()
        defer { lock.unlock() }
        refreshInternal()
    }

    private func refreshInternal() {
        var interfaces: [NetworkInterfaceInfo] = []
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else {
            return
        }
        defer { freeifaddrs(ifaddrPointer) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let name = String(cString: ptr.pointee.ifa_name)

            // Must be UP and RUNNING
            guard (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING) else {
                continue
            }

            let isLoopbackFlag = (flags & IFF_LOOPBACK) != 0

            guard let addr = ptr.pointee.ifa_addr else {
                continue
            }

            let family = addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    addr,
                    socklen_t(addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    let ip = String(cString: hostname)
                    // Strictly exclude loopback addresses (127.0.0.1, localhost)
                    let isLoopback = isLoopbackFlag || ip.hasPrefix("127.") || ip == "localhost"
                    let isLAN = isPrivateIPv4(ip)
                    interfaces.append(NetworkInterfaceInfo(
                        name: name,
                        address: ip,
                        isIPv6: false,
                        isLAN: isLAN,
                        isLoopback: isLoopback
                    ))
                }
            } else if family == UInt8(AF_INET6) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    addr,
                    socklen_t(addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    let ip = String(cString: hostname)
                    // Strictly exclude ::1 loopback
                    let isLoopback = isLoopbackFlag || ip == "::1" || ip.hasPrefix("fe80::1")
                    let isLAN = ip.hasPrefix("fe80:") || ip.hasPrefix("fc00:") || ip.hasPrefix("fd00:")
                    // Clean scope identifier (e.g. %en0) if present
                    let cleanIP = ip.components(separatedBy: "%").first ?? ip
                    interfaces.append(NetworkInterfaceInfo(
                        name: name,
                        address: cleanIP,
                        isIPv6: true,
                        isLAN: isLAN,
                        isLoopback: isLoopback
                    ))
                }
            }
        }

        self.cachedInterfaces = interfaces
        self.lastRefreshTime = Date()
    }

    private func isPrivateIPv4(_ ip: String) -> Bool {
        if ip.hasPrefix("10.") { return true }
        if ip.hasPrefix("192.168.") { return true }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), second >= 16 && second <= 31 {
                return true
            }
        }
        if ip.hasPrefix("169.254.") { return true } // Link-local
        return false
    }
}
