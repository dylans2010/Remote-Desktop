import Foundation
import UserNotifications

/// Manages local user notifications on macOS for incoming connections, pair requests, and session alerts.
public final class MacNotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = MacNotificationManager()

    public static let categoryConnectionRequest = "CONNECTION_REQUEST"
    public static let categoryPairRequest = "PAIR_REQUEST"
    public static let categorySessionEnded = "SESSION_ENDED"

    public static let actionApprove = "ACTION_APPROVE"
    public static let actionDecline = "ACTION_DECLINE"

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    /// Request notification authorization from user if not determined.
    public func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[NotificationManager] Authorization error: \(error)")
            } else {
                print("[NotificationManager] Notifications granted: \(granted)")
            }
        }
    }

    /// Register notification categories with actionable responses.
    private func registerCategories() {
        let approveAction = UNNotificationAction(
            identifier: Self.actionApprove,
            title: "Approve",
            options: [.foreground]
        )
        let declineAction = UNNotificationAction(
            identifier: Self.actionDecline,
            title: "Decline",
            options: [.destructive]
        )

        let connectionCategory = UNNotificationCategory(
            identifier: Self.categoryConnectionRequest,
            actions: [approveAction, declineAction],
            intentIdentifiers: [],
            options: []
        )

        let pairCategory = UNNotificationCategory(
            identifier: Self.categoryPairRequest,
            actions: [approveAction, declineAction],
            intentIdentifiers: [],
            options: []
        )

        let endedCategory = UNNotificationCategory(
            identifier: Self.categorySessionEnded,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([connectionCategory, pairCategory, endedCategory])
    }

    /// Post an actionable local notification for an incoming connection request.
    public func notifyIncomingConnection(peerName: String, permissionsDescription: String) {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Incoming Remote Desktop Connection"
            content.subtitle = "\(peerName) wants to connect"
            content.body = "Requested: \(permissionsDescription)"
            content.sound = .default
            content.categoryIdentifier = Self.categoryConnectionRequest

            let request = UNNotificationRequest(
                identifier: "incoming_\(UUID().uuidString)",
                content: content,
                trigger: nil // Immediate delivery
            )

            self.center.add(request)
        }
    }

    /// Post local notification when a session ends.
    public func notifySessionEnded(peerName: String, reason: String) {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Remote Desktop Session Ended"
            content.body = "\(peerName): \(reason)"
            content.sound = .default
            content.categoryIdentifier = Self.categorySessionEnded

            let request = UNNotificationRequest(
                identifier: "ended_\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            self.center.add(request)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        if actionIdentifier == Self.actionApprove {
            RemoteSessionManager.shared.respondToConnectionRequest(approved: true, permissions: .standardDefault)
        } else if actionIdentifier == Self.actionDecline {
            RemoteSessionManager.shared.respondToConnectionRequest(approved: false, permissions: .viewOnly)
        }
        completionHandler()
    }
}
