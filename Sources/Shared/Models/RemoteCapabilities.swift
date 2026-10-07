import Foundation

/// Advertised capabilities supported by a peer device.
public struct RemoteCapabilities: Codable, Sendable, Equatable, Hashable {
    public var screenViewing: Bool
    public var remoteControl: Bool
    public var clipboard: Bool
    public var fileTransfer: Bool
    public var audio: Bool
    public var multiDisplay: Bool
    public var screenBroadcast: Bool

    public init(
        screenViewing: Bool = true,
        remoteControl: Bool = false,
        clipboard: Bool = true,
        fileTransfer: Bool = true,
        audio: Bool = false,
        multiDisplay: Bool = false,
        screenBroadcast: Bool = false
    ) {
        self.screenViewing = screenViewing
        self.remoteControl = remoteControl
        self.clipboard = clipboard
        self.fileTransfer = fileTransfer
        self.audio = audio
        self.multiDisplay = multiDisplay
        self.screenBroadcast = screenBroadcast
    }

    /// Standard capabilities for macOS host/client.
    public static var macOSDefault: RemoteCapabilities {
        RemoteCapabilities(
            screenViewing: true,
            remoteControl: true,
            clipboard: true,
            fileTransfer: true,
            audio: false,
            multiDisplay: true,
            screenBroadcast: false
        )
    }

    /// Standard capabilities for iOS host/client.
    public static var iOSDefault: RemoteCapabilities {
        RemoteCapabilities(
            screenViewing: true,
            remoteControl: false,
            clipboard: true,
            fileTransfer: true,
            audio: false,
            multiDisplay: false,
            screenBroadcast: true
        )
    }
}
