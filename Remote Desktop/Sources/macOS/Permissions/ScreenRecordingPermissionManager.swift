import Foundation
import AppKit

/// Manages macOS Screen Recording authorization.
public final class ScreenRecordingPermissionManager: @unchecked Sendable {
    public static let shared = ScreenRecordingPermissionManager()

    private init() {}

    /// Check if Screen Recording permission is currently granted.
    public var isAuthorized: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    /// Prompt system for Screen Recording permission access.
    public func requestPermission() {
        if #available(macOS 10.15, *) {
            CGRequestScreenCaptureAccess()
        }
    }

    /// Open System Settings to Privacy & Security -> Screen Recording.
    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
