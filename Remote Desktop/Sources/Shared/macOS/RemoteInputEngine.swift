import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
#endif

/// Handles coordinate translation and remote CGEvent input injection on macOS host.
public final class RemoteInputEngine: @unchecked Sendable {
    public static let shared = RemoteInputEngine()

    private init() {}

    /// Maps normalized coordinates (0.0 to 1.0) on remote viewport to local macOS screen points.
    public static func mapCoordinates(
        normalizedX: Double,
        normalizedY: Double,
        targetDisplayWidth: Double,
        targetDisplayHeight: Double
    ) -> CGPoint {
        let clampedX = max(0.0, min(1.0, normalizedX))
        let clampedY = max(0.0, min(1.0, normalizedY))

        let screenX = clampedX * targetDisplayWidth
        let screenY = clampedY * targetDisplayHeight

        return CGPoint(x: screenX, y: screenY)
    }

    /// Process and inject incoming RemoteInputEvent on macOS using CGEvent APIs.
    public func injectInputEvent(_ event: RemoteInputEvent) {
        #if os(macOS)
        let mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        let width = Double(mainDisplayBounds.width)
        let height = Double(mainDisplayBounds.height)

        let point = RemoteInputEngine.mapCoordinates(
            normalizedX: event.x ?? 0.5,
            normalizedY: event.y ?? 0.5,
            targetDisplayWidth: width,
            targetDisplayHeight: height
        )

        switch event.type {
        case .mouseMove:
            if let cgEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
                cgEvent.post(tap: .cghidEventTap)
            }

        case .mouseDown:
            if let cgEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
                cgEvent.post(tap: .cghidEventTap)
            }

        case .mouseUp:
            if let cgEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
                cgEvent.post(tap: .cghidEventTap)
            }

        case .rightMouseDown:
            if let cgEvent = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right) {
                cgEvent.post(tap: .cghidEventTap)
            }

        case .rightMouseUp:
            if let cgEvent = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right) {
                cgEvent.post(tap: .cghidEventTap)
            }

        case .scroll:
            let deltaY = Int32(event.deltaY ?? 0)
            let deltaX = Int32(event.deltaX ?? 0)
            if let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0) {
                cgEvent.post(tap: .cghidEventTap)
            }

        case .keyDown:
            if let keyCode = event.keyCode {
                if let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) {
                    if let flags = event.modifiers {
                        cgEvent.flags = CGEventFlags(rawValue: UInt64(flags))
                    }
                    cgEvent.post(tap: .cghidEventTap)
                }
            }

        case .keyUp:
            if let keyCode = event.keyCode {
                if let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false) {
                    cgEvent.post(tap: .cghidEventTap)
                }
            }

        case .drag:
            if let cgEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left) {
                cgEvent.post(tap: .cghidEventTap)
            }
        }
        #endif
    }
}
