import Foundation

/// Shared clipboard synchronization manager using injected platform service.
public final class ClipboardSyncManager: @unchecked Sendable {
    public static let shared = ClipboardSyncManager()

    public var platformService: ClipboardServiceProtocol?

    public var currentPolicy: ClipboardPolicy {
        get { platformService?.currentPolicy ?? .automatic }
        set { platformService?.currentPolicy = newValue }
    }

    public var onClipboardContentChanged: ((ClipboardPayload) -> Void)? {
        get { platformService?.onClipboardContentChanged }
        set { platformService?.onClipboardContentChanged = newValue }
    }

    private init() {}

    /// Start monitoring pasteboard.
    public func startMonitoring() {
        platformService?.startMonitoring()
    }

    /// Stop monitoring pasteboard.
    public func stopMonitoring() {
        platformService?.stopMonitoring()
    }

    /// Write payload to pasteboard.
    public func writeToClipboard(_ payload: ClipboardPayload) {
        platformService?.writeToClipboard(payload)
    }

    /// Apply clipboard payload received from remote peer.
    public func applyRemoteClipboard(_ payload: ClipboardPayload) {
        writeToClipboard(payload)
    }
}
