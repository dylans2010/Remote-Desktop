import Foundation
import UIKit

/// iOS implementation of ClipboardServiceProtocol using UIPasteboard.
public final class IOSClipboardService: ClipboardServiceProtocol, @unchecked Sendable {
    public static let shared = IOSClipboardService()

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
        lastChangeCount = UIPasteboard.general.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPasteboardChange()
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    public func writeToClipboard(_ payload: ClipboardPayload) {
        guard currentPolicy != .disabled else { return }

        let pasteboard = UIPasteboard.general

        switch payload.type {
        case .text:
            if let text = payload.textContent {
                pasteboard.string = text
            }
        case .image:
            if currentPolicy == .automatic, let data = payload.dataContent, let image = UIImage(data: data) {
                pasteboard.image = image
            }
        }

        lastChangeCount = pasteboard.changeCount
    }

    private func checkPasteboardChange() {
        guard currentPolicy != .disabled else { return }

        let pasteboard = UIPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }

        lastChangeCount = pasteboard.changeCount

        if let text = pasteboard.string {
            let payload = ClipboardPayload(type: .text, textContent: text)
            onClipboardContentChanged?(payload)
        } else if currentPolicy == .automatic, let image = pasteboard.image, let data = image.jpegData(compressionQuality: 0.8) {
            let payload = ClipboardPayload(type: .image, dataContent: data)
            onClipboardContentChanged?(payload)
        }
    }
}
