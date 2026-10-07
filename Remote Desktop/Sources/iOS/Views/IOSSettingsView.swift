import SwiftUI

public struct IOSSettingsView: View {
    @AppStorage("qualityProfile") private var qualityProfileRaw: String = SessionQualityProfile.automatic.rawValue
    @AppStorage("clipboardPolicy") private var clipboardPolicyRaw: String = ClipboardPolicy.automatic.rawValue

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Display Streaming Quality")) {
                Picker("Quality Profile", selection: $qualityProfileRaw) {
                    Text("Automatic (Adaptive)").tag(SessionQualityProfile.automatic.rawValue)
                    Text("High Quality (8 Mbps)").tag(SessionQualityProfile.high.rawValue)
                    Text("Balanced (4 Mbps)").tag(SessionQualityProfile.balanced.rawValue)
                    Text("Low Latency (60 FPS)").tag(SessionQualityProfile.lowLatency.rawValue)
                }
            }

            Section(header: Text("Clipboard Sync")) {
                Picker("Clipboard Mode", selection: $clipboardPolicyRaw) {
                    Text("Automatic").tag(ClipboardPolicy.automatic.rawValue)
                    Text("Text Only").tag(ClipboardPolicy.textOnly.rawValue)
                    Text("Disabled").tag(ClipboardPolicy.disabled.rawValue)
                }
            }

            Section(header: Text("About")) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Platform")
                    Spacer()
                    Text("iOS / iPadOS")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}
