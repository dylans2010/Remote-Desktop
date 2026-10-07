import Foundation
import AppKit

/// Manages macOS Accessibility authorization required for remote mouse/keyboard control.
public final class AccessibilityPermissionManager: @unchecked Sendable {
    public static let shared = AccessibilityPermissionManager()

    private init() {}

    /// Check if Accessibility permission is granted for remote input control.
    public var isAuthorized: Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Request Accessibility permission prompt.
    public func requestPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings to Privacy & Security -> Accessibility.
    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
