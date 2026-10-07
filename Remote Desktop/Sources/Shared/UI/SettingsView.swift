import SwiftUI

public struct SettingsView: View {
    @AppStorage("allowConnections") private var allowConnections: Bool = true
    @AppStorage("requireApproval") private var requireApproval: Bool = true
    @AppStorage("allowUnattended") private var allowUnattended: Bool = false
    @AppStorage("qualityProfile") private var qualityProfileRaw: String = SessionQualityProfile.automatic.rawValue
    @AppStorage("clipboardPolicy") private var clipboardPolicyRaw: String = ClipboardPolicy.automatic.rawValue
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false

    @ObservedObject var permissionsManager = PermissionsViewModel()

    public init() {}

    public var body: some View {
        TabView {
            // General Settings
            Form {
                Section(header: Text("Application")) {
                    Toggle("Launch Remote Desktop at login", isOn: $launchAtLogin)
                }

                Section(header: Text("Permissions Status")) {
                    HStack {
                        Text("Screen Recording")
                        Spacer()
                        if permissionsManager.hasScreenRecording {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Grant Access") {
                                PermissionsManager.shared.requestScreenRecordingPermission()
                            }
                        }
                    }

                    HStack {
                        Text("Accessibility (Remote Control)")
                        Spacer()
                        if permissionsManager.hasAccessibility {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Grant Access") {
                                PermissionsManager.shared.requestAccessibilityPermission()
                            }
                        }
                    }
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            .padding(16)

            // Remote Access Settings
            Form {
                Section(header: Text("Incoming Connections")) {
                    Toggle("Allow remote access to this Mac", isOn: $allowConnections)
                    Toggle("Require explicit approval for connections", isOn: $requireApproval)
                }

                Section(header: Text("Unattended Access")) {
                    Toggle("Enable Unattended Access for trusted devices", isOn: $allowUnattended)
                    Text("Trusted devices will be able to connect without manual prompt on this Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tabItem { Label("Remote Access", systemImage: "macbook.and.iphone") }
            .padding(16)

            // Streaming Quality Settings
            Form {
                Section(header: Text("Display Streaming Quality")) {
                    Picker("Streaming Quality Profile", selection: $qualityProfileRaw) {
                        Text("Automatic (Adaptive)").tag(SessionQualityProfile.automatic.rawValue)
                        Text("High Quality (8 Mbps)").tag(SessionQualityProfile.high.rawValue)
                        Text("Balanced (4 Mbps)").tag(SessionQualityProfile.balanced.rawValue)
                        Text("Low Latency (60 FPS)").tag(SessionQualityProfile.lowLatency.rawValue)
                    }
                    .pickerStyle(.radioGroup)
                }
            }
            .tabItem { Label("Quality", systemImage: "slider.horizontal.3") }
            .padding(16)

            // Clipboard Settings
            Form {
                Section(header: Text("Clipboard Synchronization")) {
                    Picker("Clipboard Mode", selection: $clipboardPolicyRaw) {
                        Text("Automatic (Text & Images)").tag(ClipboardPolicy.automatic.rawValue)
                        Text("Text Only").tag(ClipboardPolicy.textOnly.rawValue)
                        Text("Disabled").tag(ClipboardPolicy.disabled.rawValue)
                    }
                    .pickerStyle(.radioGroup)
                }
            }
            .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            .padding(16)
        }
        .frame(width: 520, height: 320)
    }
}

final class PermissionsViewModel: ObservableObject, @unchecked Sendable {
    @Published var hasScreenRecording: Bool = false
    @Published var hasAccessibility: Bool = false

    init() {
        refresh()
    }

    func refresh() {
        hasScreenRecording = PermissionsManager.shared.hasScreenRecordingPermission
        hasAccessibility = PermissionsManager.shared.hasAccessibilityPermission
    }
}
