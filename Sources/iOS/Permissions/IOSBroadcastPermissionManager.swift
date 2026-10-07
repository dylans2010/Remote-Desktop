import Foundation
import ReplayKit

/// Checks and manages iOS Screen Broadcast / ReplayKit permissions.
public final class IOSBroadcastPermissionManager: @unchecked Sendable {
    public static let shared = IOSBroadcastPermissionManager()

    private init() {}

    /// Verify whether RPScreenRecorder is available for broadcasting on this iOS device.
    public var isBroadcastAvailable: Bool {
        return RPScreenRecorder.shared().isAvailable
    }
}
