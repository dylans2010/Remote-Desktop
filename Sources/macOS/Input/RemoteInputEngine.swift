import Foundation
import CoreGraphics
import AppKit

/// Handles coordinate translation and CGEvent input injection on macOS host.
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

    /// Process and inject incoming RemoteInputEvent on macOS using CGEvent APIs after permission check.
    public func injectInputEvent(_ event: RemoteInputEvent) {
        guard AccessibilityPermissionManager.shared.isAuthorized else {
            print("[RemoteInputEngine] Accessibility authorization missing. Refusing remote input injection.")
            return
        }

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
            let mouseEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
            mouseEvent?.post(tap: .cghidEventTap)

        case .mouseDown:
            let mouseDownEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
            mouseDownEvent?.post(tap: .cghidEventTap)

        case .mouseUp:
            let mouseUpEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
            mouseUpEvent?.post(tap: .cghidEventTap)

        case .rightMouseDown:
            let mouseDownEvent = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)
            mouseDownEvent?.post(tap: .cghidEventTap)

        case .rightMouseUp:
            let mouseUpEvent = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)
            mouseUpEvent?.post(tap: .cghidEventTap)

        case .drag:
            let dragEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)
            dragEvent?.post(tap: .cghidEventTap)

        case .scroll:
            let deltaY = Int32(event.deltaY ?? 0.0)
            let deltaX = Int32(event.deltaX ?? 0.0)
            let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0)
            scrollEvent?.post(tap: .cghidEventTap)

        case .keyDown:
            if let keyCode = event.keyCode {
                let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)
                if let modifiers = event.modifiers {
                    keyDown?.flags = CGEventFlags(rawValue: UInt64(modifiers))
                }
                keyDown?.post(tap: .cghidEventTap)
            }

        case .keyUp:
            if let keyCode = event.keyCode {
                let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false)
                if let modifiers = event.modifiers {
                    keyUp?.flags = CGEventFlags(rawValue: UInt64(modifiers))
                }
                keyUp?.post(tap: .cghidEventTap)
            }
        }
    }
}
