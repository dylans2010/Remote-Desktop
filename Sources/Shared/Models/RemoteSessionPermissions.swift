import Foundation

/// Granular capability permissions for a remote desktop session.
public struct RemoteSessionPermissions: Codable, Sendable, Equatable, Hashable {
    public var viewScreen: Bool
    public var controlScreen: Bool
    public var keyboard: Bool
    public var mouse: Bool
    public var clipboard: Bool
    public var fileTransfer: Bool
    public var audio: Bool
    public var annotation: Bool

    public init(
        viewScreen: Bool = true,
        controlScreen: Bool = false,
        keyboard: Bool = false,
        mouse: Bool = false,
        clipboard: Bool = false,
        fileTransfer: Bool = false,
        audio: Bool = false,
        annotation: Bool = false
    ) {
        self.viewScreen = viewScreen
        self.controlScreen = controlScreen
        self.keyboard = keyboard
        self.mouse = mouse
        self.clipboard = clipboard
        self.fileTransfer = fileTransfer
        self.audio = audio
        self.annotation = annotation
    }

    // MARK: - Presets

    /// View Only preset: Remote viewer can see screen, but cannot control, draw, or transfer files.
    public static var viewOnly: RemoteSessionPermissions {
        RemoteSessionPermissions(
            viewScreen: true,
            controlScreen: false,
            keyboard: false,
            mouse: false,
            clipboard: false,
            fileTransfer: false,
            audio: false,
            annotation: false
        )
    }

    /// Teaching preset: Remote viewer can view screen and draw annotations to point out areas, but cannot inject input or touch files.
    public static var teaching: RemoteSessionPermissions {
        RemoteSessionPermissions(
            viewScreen: true,
            controlScreen: false,
            keyboard: false,
            mouse: false,
            clipboard: false,
            fileTransfer: false,
            audio: false,
            annotation: true
        )
    }

    /// Full Remote Control preset: Remote viewer can view, control mouse, type with keyboard, sync clipboard, transfer files, and annotate.
    public static var fullControl: RemoteSessionPermissions {
        RemoteSessionPermissions(
            viewScreen: true,
            controlScreen: true,
            keyboard: true,
            mouse: true,
            clipboard: true,
            fileTransfer: true,
            audio: false,
            annotation: true
        )
    }

    /// Standard default permissions for a newly paired device.
    public static var standardDefault: RemoteSessionPermissions {
        RemoteSessionPermissions(
            viewScreen: true,
            controlScreen: true,
            keyboard: true,
            mouse: true,
            clipboard: false,
            fileTransfer: false,
            audio: false,
            annotation: true
        )
    }

    // MARK: - Authorization Verification Helpers

    /// Checks if a remote input event type is authorized under these permissions.
    public func isInputAuthorized(for type: RemoteInputEvent.InputType) -> Bool {
        guard controlScreen else { return false }
        switch type {
        case .mouseMove, .mouseDown, .mouseUp, .rightMouseDown, .rightMouseUp, .scroll, .drag:
            return mouse
        case .keyDown, .keyUp:
            return keyboard
        }
    }

    /// Verifies if drawing/annotation events are permitted.
    public var isAnnotationAuthorized: Bool {
        return annotation
    }

    /// Verifies if clipboard synchronization is permitted.
    public var isClipboardAuthorized: Bool {
        return clipboard
    }

    /// Verifies if file transfer is permitted.
    public var isFileTransferAuthorized: Bool {
        return fileTransfer
    }
}

/// Convenience presets for session setup and dynamic switching.
public enum SessionPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case viewOnly = "View Only"
    case teaching = "Teaching"
    case fullControl = "Remote Control"
    case custom = "Custom"

    public var id: String { rawValue }

    public var permissions: RemoteSessionPermissions {
        switch self {
        case .viewOnly:
            return .viewOnly
        case .teaching:
            return .teaching
        case .fullControl:
            return .fullControl
        case .custom:
            return .standardDefault
        }
    }
}
