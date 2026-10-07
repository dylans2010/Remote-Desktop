import Foundation

/// Policy options for clipboard synchronization.
public enum ClipboardPolicy: String, Codable, Sendable {
    case disabled
    case textOnly
    case automatic
}

/// Abstract contract for platform-specific clipboard operations.
public protocol ClipboardServiceProtocol: AnyObject, Sendable {
    var currentPolicy: ClipboardPolicy { get set }
    var onClipboardContentChanged: ((ClipboardPayload) -> Void)? { get set }

    func startMonitoring()
    func stopMonitoring()
    func writeToClipboard(_ payload: ClipboardPayload)
}
