import Foundation
import AppKit

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

/// Manages background host service availability, incoming connection approval prompts, and macOS menu bar status.
public final class HostModeManager: @unchecked Sendable {
    public static let shared = HostModeManager()

    public var config = HostAccessConfig()
    public var onRequestIncomingConnection: (@Sendable (Device, RemoteSessionPermissions, @escaping @Sendable (Bool, RemoteSessionPermissions) -> Void) -> Void)?

    private var statusItem: NSStatusItem?
    private let lock = NSLock()

    private init() {}

    /// Get current hostname.
    public static func hostDeviceName() -> String {
        return Host.current().localizedName ?? "My Mac"
    }

    /// Setup macOS menu bar NSStatusItem icon.
    public func setupStatusItem() {
        DispatchQueue.main.async {
            guard self.statusItem == nil else { return }
            self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = self.statusItem?.button {
                button.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "Remote Desktop")
            }
            self.updateStatusItem(peerName: nil, permissions: nil)
        }
    }

    /// Dynamically update menu bar item to reflect active session status.
    public func updateStatusItem(peerName: String?, permissions: RemoteSessionPermissions?) {
        DispatchQueue.main.async {
            guard let statusItem = self.statusItem else { return }

            let menu = NSMenu()

            if let peer = peerName {
                // Active session display
                let activeItem = NSMenuItem(title: "Remote Desktop: Active Session", action: nil, keyEquivalent: "")
                activeItem.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Active")
                menu.addItem(activeItem)

                menu.addItem(NSMenuItem(title: "Connected: \(peer)", action: nil, keyEquivalent: ""))

                if let perms = permissions {
                    let permText = perms.controlScreen ? "Viewing & Controlling" : "View Only"
                    menu.addItem(NSMenuItem(title: "Permissions: \(permText)", action: nil, keyEquivalent: ""))
                }

                menu.addItem(NSMenuItem.separator())

                let stopItem = NSMenuItem(title: "Stop Session", action: #selector(self.stopActiveSession), keyEquivalent: "s")
                stopItem.target = self
                menu.addItem(stopItem)
            } else {
                // Idle display
                menu.addItem(NSMenuItem(title: "Remote Desktop: Ready", action: nil, keyEquivalent: ""))
            }

            menu.addItem(NSMenuItem.separator())
            let settingsItem = NSMenuItem(title: "Settings...", action: #selector(self.openSettings), keyEquivalent: ",")
            settingsItem.target = self
            menu.addItem(settingsItem)

            menu.addItem(NSMenuItem.separator())
            let quitItem = NSMenuItem(title: "Quit Remote Desktop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            menu.addItem(quitItem)

            statusItem.menu = menu
        }
    }

    @objc private func stopActiveSession() {
        RemoteSessionManager.shared.endSession(reason: "Host stopped session from menu bar")
    }

    @MainActor @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// Process incoming session request from remote peer.
    public func handleIncomingSessionRequest(from peer: Device, completion: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        let currentConfig = config
        lock.unlock()

        guard currentConfig.allowConnections else {
            completion(false)
            return
        }

        if TrustModel.shared.isTrusted(deviceID: peer.id) && currentConfig.allowUnattendedAccess {
            completion(true)
            return
        }

        if currentConfig.requireApproval {
            if let customHandler = onRequestIncomingConnection {
                customHandler(peer, .standardDefault) { approved, _ in
                    completion(approved)
                }
            } else {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Incoming Remote Desktop Connection"
                    alert.informativeText = "\(peer.name) wants to connect to and view this Mac."
                    alert.addButton(withTitle: "Accept")
                    alert.addButton(withTitle: "Decline")
                    let response = alert.runModal()
                    completion(response == .alertFirstButtonReturn)
                }
            }
        } else {
            completion(true)
        }
    }
}
