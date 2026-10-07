import Foundation

#if os(macOS)
import AppKit
#endif

/// Checks and manages macOS system permissions required for Remote Desktop (Screen Recording & Accessibility).
public final class PermissionsManager: @unchecked Sendable {
    public static let shared = PermissionsManager()

    private init() {}

    /// Check if Screen Recording permission is currently granted.
    public var hasScreenRecordingPermission: Bool {
        #if os(macOS)
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
        #else
        return true
        #endif
    }

    /// Request Screen Recording permission prompt.
    public func requestScreenRecordingPermission() {
        #if os(macOS)
        if #available(macOS 10.15, *) {
            CGRequestScreenCaptureAccess()
        }
        #endif
    }

    /// Check if Accessibility (Remote Input Control) permission is granted.
    public var hasAccessibilityPermission: Bool {
        #if os(macOS)
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
        #else
        return true
        #endif
    }

    /// Request Accessibility permission prompt.
    public func requestAccessibilityPermission() {
        #if os(macOS)
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
        #endif
    }

    /// Open macOS System Settings directly to relevant Privacy & Security panel.
    public func openSystemPrivacySettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
