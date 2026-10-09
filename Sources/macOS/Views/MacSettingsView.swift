import SwiftUI

public struct MacSettingsView: View {
    @AppStorage("allowConnections") private var allowConnections: Bool = true
    @AppStorage("requireApproval") private var requireApproval: Bool = true
    @AppStorage("allowUnattended") private var allowUnattended: Bool = false
    @AppStorage("qualityProfile") private var qualityProfileRaw: String = SessionQualityProfile.automatic.rawValue
    @AppStorage("clipboardPolicy") private var clipboardPolicyRaw: String = ClipboardPolicy.automatic.rawValue
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false

    @StateObject private var permissionsManager = MacPermissionsViewModel()

    public init() {}

    public var body: some View {
        TabView {
            // General Settings
            Form {
                // Branding Header
                HStack(spacing: 14) {
                    ZStack {
                        LinearGradient(
                            colors: [Color.blue, Color.indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Image(systemName: "macbook.and.iphone")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remote Desktop for Mac")
                            .font(.headline)

                        HStack(spacing: 6) {
                            Text("P2P Mesh")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .clipShape(Capsule())

                            Text("AES-256")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())

                            Text("Bonjour")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15))
                                .foregroundColor(.purple)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.bottom, 6)

                Section {
                    Toggle("Launch Remote Desktop at system login", isOn: $launchAtLogin)
                } header: {
                    Label("Startup", systemImage: "power")
                        .font(.footnote.weight(.semibold))
                }

                Section {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "display")
                                .foregroundColor(.blue)
                            Text("Screen Recording")
                        }
                        Spacer()
                        if permissionsManager.hasScreenRecording {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Grant Access") {
                                ScreenRecordingPermissionManager.shared.requestPermission()
                                permissionsManager.refresh()
                            }
                        }
                    }

                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(.indigo)
                            Text("Accessibility (Remote Control)")
                        }
                        Spacer()
                        if permissionsManager.hasAccessibility {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Grant Access") {
                                AccessibilityPermissionManager.shared.requestPermission()
                                permissionsManager.refresh()
                            }
                        }
                    }
                } header: {
                    Label("Host System Permissions", systemImage: "lock.shield")
                        .font(.footnote.weight(.semibold))
                }
            }
            .tabItem { Label("General", systemImage: "gearshape.fill") }
            .padding(16)

            // Remote Access Settings
            Form {
                Section {
                    Toggle("Allow remote access to this Mac", isOn: $allowConnections)
                    Toggle("Require explicit approval for connections", isOn: $requireApproval)
                } header: {
                    Label("Incoming Requests", systemImage: "arrow.down.left.circle")
                        .font(.footnote.weight(.semibold))
                }

                Section {
                    Toggle("Enable Unattended Access for trusted devices", isOn: $allowUnattended)
                    Text("Trusted devices will connect without displaying a confirmation prompt on this Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Label("Unattended Access", systemImage: "key.fill")
                        .font(.footnote.weight(.semibold))
                }
            }
            .tabItem { Label("Remote Access", systemImage: "macbook.and.iphone") }
            .padding(16)

            // Streaming Quality Settings
            Form {
                Section {
                    Picker("Streaming Profile", selection: $qualityProfileRaw) {
                        Text("Automatic (Adaptive Bitrate & Resolution)").tag(SessionQualityProfile.automatic.rawValue)
                        Text("High Quality (8 Mbps)").tag(SessionQualityProfile.high.rawValue)
                        Text("Balanced (4 Mbps)").tag(SessionQualityProfile.balanced.rawValue)
                        Text("Low Latency (60 FPS prioritized)").tag(SessionQualityProfile.lowLatency.rawValue)
                    }
                    .pickerStyle(.radioGroup)

                    Text("Adaptive dynamically calculates RTT latency and packet loss to deliver fluid video.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                } header: {
                    Label("Display Streaming Quality", systemImage: "video.fill")
                        .font(.footnote.weight(.semibold))
                }
            }
            .tabItem { Label("Quality", systemImage: "slider.horizontal.3") }
            .padding(16)

            // Clipboard Settings
            Form {
                Section {
                    Picker("Clipboard Mode", selection: $clipboardPolicyRaw) {
                        Text("Automatic (Text & Images)").tag(ClipboardPolicy.automatic.rawValue)
                        Text("Text Only").tag(ClipboardPolicy.textOnly.rawValue)
                        Text("Disabled").tag(ClipboardPolicy.disabled.rawValue)
                    }
                    .pickerStyle(.radioGroup)

                    Text("Synchronizes clipboard contents over the encrypted transport.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                } header: {
                    Label("Clipboard Synchronization", systemImage: "doc.on.clipboard.fill")
                        .font(.footnote.weight(.semibold))
                }
            }
            .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard.fill") }
            .padding(16)
        }
        .frame(width: 540, height: 360)
        .onAppear {
            permissionsManager.refresh()
        }
    }
}

final class MacPermissionsViewModel: ObservableObject, @unchecked Sendable {
    @Published var hasScreenRecording: Bool = false
    @Published var hasAccessibility: Bool = false

    init() {
        refresh()
    }

    func refresh() {
        hasScreenRecording = ScreenRecordingPermissionManager.shared.isAuthorized
        hasAccessibility = AccessibilityPermissionManager.shared.isAuthorized
    }
}
