import Foundation

#if os(macOS)
import AppKit
#endif

/// Configuration for Host Mode availability and approval settings.
public struct HostAccessConfig: Codable, Sendable {
    public var allowConnections: Bool = true
    public var requireApproval: Bool = true
    public var allowUnattendedAccess: Bool = false
    public var unattendedPasswordHash: String? = nil

    public init(
        allowConnections: Bool = true,
        requireApproval: Bool = true,
        allowUnattendedAccess: Bool = false,
        unattendedPasswordHash: String? = nil
    ) {
        self.allowConnections = allowConnections
        self.requireApproval = requireApproval
        self.allowUnattendedAccess = allowUnattendedAccess
        self.unattendedPasswordHash = unattendedPasswordHash
    }
}

/// Manages background host service availability, incoming connection approval prompts, and unattended access rules.
public final class HostModeManager: @unchecked Sendable {
    public static let shared = HostModeManager()

    public var config = HostAccessConfig()
    public var onRequestIncomingConnection: ((Device, @escaping (Bool) -> Void) -> Void)?

    #if os(macOS)
    private var statusItem: NSStatusItem?
    #endif
    private let lock = NSLock()

    private init() {}

    /// Enable background host mode and menu bar status indicator.
    public func startHostService(identity: DeviceIdentity) {
        lock.lock()
        defer { lock.unlock() }

        // Start Bonjour advertising
        BonjourDiscoveryManager().startAdvertising(identity: identity)

        #if os(macOS)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = self.statusItem?.button {
                button.title = "● Remote Desktop"
            }

            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Remote Access: Active", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Open Remote Desktop", action: #selector(self.openApp), keyEquivalent: "o"))
            menu.addItem(NSMenuItem(title: "Disable Remote Access", action: #selector(self.disableHost), keyEquivalent: "d"))

            self.statusItem?.menu = menu
        }
        #endif
        print("[HostModeManager] Host mode service started")
    }

    /// Process incoming session request and prompt user or check unattended access policy.
    public func handleIncomingSessionRequest(from peer: Device, completion: @escaping (Bool) -> Void) {
        lock.lock()
        let currentConfig = config
        lock.unlock()

        guard currentConfig.allowConnections else {
            completion(false)
            return
        }

        if currentConfig.allowUnattendedAccess && TrustModel.shared.isTrusted(deviceID: peer.id) {
            completion(true)
            return
        }

        if currentConfig.requireApproval {
            if let promptHandler = onRequestIncomingConnection {
                promptHandler(peer, completion)
            } else {
                completion(false)
            }
        } else {
            completion(true)
        }
    }

    #if os(macOS)
    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func disableHost() {
        lock.lock()
        config.allowConnections = false
        lock.unlock()
        print("[HostModeManager] Host access disabled via menu bar")
    }
    #endif
}
