import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// User-defined Clipboard policy options.
public enum ClipboardPolicy: String, Codable, Sendable {
    case disabled
    case textOnly
    case automatic
}

/// Manages system clipboard monitoring and end-to-end synchronized pasteboard events.
public final class ClipboardSyncManager: @unchecked Sendable {
    public static let shared = ClipboardSyncManager()

    public var currentPolicy: ClipboardPolicy = .automatic
    public var onClipboardContentChanged: ((ClipboardPayload) -> Void)?

    private var lastChangeCount: Int = -1
    private var timer: Timer?
    private let lock = NSLock()

    private init() {}

    /// Start monitoring local pasteboard changes.
    public func startMonitoring() {
        lock.lock()
        defer { lock.unlock() }

        stopMonitoring()

        #if os(macOS)
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.checkPasteboardChange()
        }
        #endif
    }

    /// Stop monitoring pasteboard.
    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Check for pasteboard updates.
    private func checkPasteboardChange() {
        guard currentPolicy != .disabled else { return }

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let text = pasteboard.string(forType: .string) {
            let payload = ClipboardPayload(type: .text, textContent: text)
            onClipboardContentChanged?(payload)
        }
        #endif
    }

    /// Apply received remote clipboard payload to local system pasteboard.
    public func applyRemoteClipboard(_ payload: ClipboardPayload) {
        guard currentPolicy != .disabled else { return }

        if currentPolicy == .textOnly && payload.type != .text {
            return
        }

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if payload.type == .text, let text = payload.textContent {
            pasteboard.setString(text, forType: .string)
            lastChangeCount = pasteboard.changeCount
        }
        #elseif os(iOS)
        if payload.type == .text, let text = payload.textContent {
            UIPasteboard.general.string = text
        }
        #endif
    }
}
