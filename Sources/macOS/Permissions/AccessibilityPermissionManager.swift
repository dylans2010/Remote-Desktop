import Foundation
import AppKit

/// Manages macOS Accessibility authorization required for remote mouse/keyboard control.
public final class AccessibilityPermissionManager: @unchecked Sendable {
    public static let shared = AccessibilityPermissionManager()

    private init() {}

    /// Check if Accessibility permission is granted for remote input control.
    public var isAuthorized: Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Request Accessibility permission prompt.
    public func requestPermission() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings to Privacy & Security -> Accessibility.
    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
