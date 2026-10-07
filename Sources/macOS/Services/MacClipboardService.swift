import Foundation
import AppKit

/// macOS implementation of ClipboardServiceProtocol using NSPasteboard.
public final class MacClipboardService: ClipboardServiceProtocol, @unchecked Sendable {
    public static let shared = MacClipboardService()

    public var currentPolicy: ClipboardPolicy = .automatic
    public var onClipboardContentChanged: ((ClipboardPayload) -> Void)?

    private var lastChangeCount: Int = -1
    private var timer: Timer?
    private let lock = NSLock()

    private init() {}

    public func startMonitoring() {
        lock.lock()
        defer { lock.unlock() }

        stopMonitoring()
        lastChangeCount = NSPasteboard.general.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.checkPasteboardChange()
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    public func writeToClipboard(_ payload: ClipboardPayload) {
        guard currentPolicy != .disabled else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch payload.type {
        case .text:
            if let text = payload.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if currentPolicy == .automatic, let data = payload.dataContent, let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        }

        lastChangeCount = pasteboard.changeCount
    }

    private func checkPasteboardChange() {
        guard currentPolicy != .disabled else { return }

        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }

        lastChangeCount = pasteboard.changeCount

        if let text = pasteboard.string(forType: .string) {
            let payload = ClipboardPayload(type: .text, textContent: text)
            onClipboardContentChanged?(payload)
        } else if currentPolicy == .automatic, let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation {
            let payload = ClipboardPayload(type: .image, dataContent: data)
            onClipboardContentChanged?(payload)
        }
    }
}
