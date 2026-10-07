import SwiftUI
import ReplayKit

/// UIViewRepresentable wrapping RPSystemBroadcastPickerView for triggering Broadcast Upload Extension.
public struct BroadcastPickerView: UIViewRepresentable {
    public var preferredExtensionBundleID: String?

    public init(preferredExtensionBundleID: String? = nil) {
        self.preferredExtensionBundleID = preferredExtensionBundleID
    }

    public func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = preferredExtensionBundleID
        picker.showsMicrophoneButton = false
        return picker
    }

    public func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
