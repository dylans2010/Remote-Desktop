import SwiftUI

public struct IOSSettingsView: View {
    @AppStorage("qualityProfile") private var qualityProfileRaw: String = SessionQualityProfile.automatic.rawValue
    @AppStorage("clipboardPolicy") private var clipboardPolicyRaw: String = ClipboardPolicy.automatic.rawValue
    @State private var showingClearTrustConfirmation: Bool = false

    public init() {}

    public var body: some View {
        Form {
            // App Branding Banner
            Section {
                HStack(spacing: 16) {
                    ZStack {
                        LinearGradient(
                            colors: [Color.blue, Color.indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)

                        Image(systemName: "macbook.and.iphone")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Remote Desktop")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("High-performance local & remote streaming")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            Text("P2P Mesh")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .clipShape(Capsule())

                            Text("AES-256")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Streaming Quality Section
            Section {
                Picker(selection: $qualityProfileRaw) {
                    Label("Automatic (Adaptive)", systemImage: "sparkles")
                        .tag(SessionQualityProfile.automatic.rawValue)
                    Label("High Quality (8 Mbps)", systemImage: "aqi.high")
                        .tag(SessionQualityProfile.high.rawValue)
                    Label("Balanced (4 Mbps)", systemImage: "aqi.medium")
                        .tag(SessionQualityProfile.balanced.rawValue)
                    Label("Low Latency (60 FPS)", systemImage: "bolt.fill")
                        .tag(SessionQualityProfile.lowLatency.rawValue)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "video.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text("Profile")
                    }
                }
            } header: {
                Label("Display Streaming Quality", systemImage: "tv")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(nil)
            } footer: {
                Text("Adaptive dynamically adjusts video bitrate and resolution based on real-time network conditions.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Clipboard Sync Section
            Section {
                Picker(selection: $clipboardPolicyRaw) {
                    Label("Automatic", systemImage: "arrow.triangle.2.circlepath")
                        .tag(ClipboardPolicy.automatic.rawValue)
                    Label("Text Only", systemImage: "text.quote")
                        .tag(ClipboardPolicy.textOnly.rawValue)
                    Label("Disabled", systemImage: "slash.circle")
                        .tag(ClipboardPolicy.disabled.rawValue)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text("Sync Mode")
                    }
                }
            } header: {
                Label("Clipboard Synchronization", systemImage: "doc.on.clipboard")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(nil)
            } footer: {
                Text("Copies on your Mac or iOS device are mirrored seamlessly over the encrypted session.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Security & Protocol Info Section
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("Encryption")
                    Spacer()
                    Text("AES-GCM 256")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }

                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("Discovery")
                    Spacer()
                    Text("Bonjour mDNS")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }

                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("Key Exchange")
                    Spacer()
                    Text("ECDH P-256")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            } header: {
                Label("Security & Architecture", systemImage: "shield.checkered")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(nil)
            }

            // About Section
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }

                HStack(spacing: 12) {
                    Image(systemName: "applelogo")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("Platform")
                    Spacer()
                    Text("iOS 18+ / iPadOS")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            } header: {
                Label("About", systemImage: "info.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(nil)
            }
        }
        .navigationTitle("Settings")
    }
}
