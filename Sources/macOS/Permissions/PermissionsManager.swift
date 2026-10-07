import Foundation
import AppKit

/// Convenience facade for macOS permissions.
public final class PermissionsManager: @unchecked Sendable {
    public static let shared = PermissionsManager()

    private init() {}

    public var hasScreenRecordingPermission: Bool {
        return ScreenRecordingPermissionManager.shared.isAuthorized
    }

    public func requestScreenRecordingPermission() {
        ScreenRecordingPermissionManager.shared.requestPermission()
    }

    public var hasAccessibilityPermission: Bool {
        return AccessibilityPermissionManager.shared.isAuthorized
    }

    public func requestAccessibilityPermission() {
        AccessibilityPermissionManager.shared.requestPermission()
    }

    public func openSystemPrivacySettings() {
        AccessibilityPermissionManager.shared.openSystemSettings()
    }
}
