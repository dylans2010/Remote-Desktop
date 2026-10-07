import SwiftUI

/// iOS Connection & Media Pipeline Diagnostics Modal.
public struct IOSDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    public let metrics: MediaHealthMetrics
    public let permissions: RemoteSessionPermissions
    public let peerName: String
    public let isHost: Bool

    public init(metrics: MediaHealthMetrics, permissions: RemoteSessionPermissions, peerName: String, isHost: Bool = false) {
        self.metrics = metrics
        self.permissions = permissions
        self.peerName = peerName
        self.isHost = isHost
    }

    public var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Pipeline Assessment")) {
                    let stage = metrics.diagnosePipeline(isHost: isHost)
                    HStack(spacing: 12) {
                        Image(systemName: stage == .healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(stage == .healthy ? .green : .orange)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stage == .healthy ? "Operating Normally" : "Pipeline Attention Needed")
                                .font(.headline)
                            Text(stage.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Network & Video Performance")) {
                    row(title: "Connection Mode", value: "Direct LAN P2P")
                    row(title: "Round Trip Time (RTT)", value: "\(Int(metrics.rttMs)) ms")
                    row(title: "Framerate", value: String(format: "%.1f FPS", metrics.currentFps))
                    row(title: "Bitrate", value: String(format: "%.1f Mbps", metrics.bitrateMbps))
                }

                Section(header: Text("Frame Delivery Pipeline")) {
                    if isHost {
                        row(title: "Frames Captured", value: "\(metrics.framesCaptured)")
                        row(title: "Frames Encoded", value: "\(metrics.framesEncoded)")
                        row(title: "Frames Sent", value: "\(metrics.framesSent)")
                    } else {
                        row(title: "Frames Received", value: "\(metrics.framesReceived)")
                        row(title: "Frames Decoded", value: "\(metrics.framesDecoded)")
                        row(title: "Frames Rendered", value: "\(metrics.framesRendered)")
                        row(title: "Packet Loss", value: String(format: "%.1f%%", metrics.packetLossPercent))
                    }
                    row(title: "Codec", value: metrics.codec)
                }

                Section(header: Text("Active Permissions")) {
                    row(title: "Screen Viewing", value: permissions.viewScreen ? "Allowed" : "Denied")
                    row(title: "Remote Control", value: permissions.controlScreen ? "Allowed" : "Denied")
                    row(title: "Drawing / Annotation", value: permissions.annotation ? "Allowed" : "Denied")
                    row(title: "Clipboard Sync", value: permissions.clipboard ? "Allowed" : "Denied")
                }
            }
            .navigationTitle("Session Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .bold()
        }
    }
}
