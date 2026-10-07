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

/// Manages background host service availability, incoming connection approval prompts, and unattended access rules.
public final class HostModeManager: @unchecked Sendable {
    public static let shared = HostModeManager()

    public var config = HostAccessConfig()
    public var onRequestIncomingConnection: ((Device, @escaping (Bool) -> Void) -> Void)?

    private var statusItem: NSStatusItem?
    private let lock = NSLock()

    private init() {}

    /// Setup macOS menu bar NSStatusItem icon.
    public func setupStatusItem() {
        DispatchQueue.main.async {
            guard self.statusItem == nil else { return }
            self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = self.statusItem?.button {
                button.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "Remote Desktop")
            }

            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Remote Desktop: Active", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Settings...", action: #selector(self.openSettings), keyEquivalent: ","))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

            for item in menu.items {
                item.target = self
            }
            self.statusItem?.menu = menu
        }
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// Process incoming session request from remote peer.
    public func handleIncomingSessionRequest(from peer: Device, completion: @escaping (Bool) -> Void) {
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
                customHandler(peer, completion)
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
