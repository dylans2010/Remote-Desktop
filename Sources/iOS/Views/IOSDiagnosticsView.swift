import SwiftUI

/// iOS Connection & Media Pipeline Diagnostics Modal.
public struct IOSDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    public let metrics: MediaHealthMetrics
    public let permissions: RemoteSessionPermissions
    public let peerName: String
    public let isHost: Bool
    public let transportDiagnostics: TransportDiagnostics
    public let connectionDiagnostics: ConnectionDiagnosticsSnapshot

    public init(
        metrics: MediaHealthMetrics,
        permissions: RemoteSessionPermissions,
        peerName: String,
        isHost: Bool = false,
        transportDiagnostics: TransportDiagnostics? = nil,
        connectionDiagnostics: ConnectionDiagnosticsSnapshot? = nil
    ) {
        self.metrics = metrics
        self.permissions = permissions
        self.peerName = peerName
        self.isHost = isHost
        self.transportDiagnostics = transportDiagnostics ?? RemoteSessionManager.shared.activeTransport?.diagnostics ?? TransportDiagnostics()
        self.connectionDiagnostics = connectionDiagnostics ?? RemoteSessionManager.shared.connectionDiagnosticsSnapshot(peerName: peerName)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Connection Diagnostics")) {
                    row(title: "Peer", value: connectionDiagnostics.peerName)
                    row(title: "Device Identity", value: connectionDiagnostics.deviceIdentityStatus)
                    row(title: "Pairing", value: connectionDiagnostics.pairingStatus)
                    row(title: "Endpoint", value: connectionDiagnostics.endpoint)
                    row(title: "Endpoint Source", value: connectionDiagnostics.endpointSource)
                    row(title: "Reachability", value: connectionDiagnostics.reachability)
                    row(title: "Transport", value: connectionDiagnostics.transportState)
                    row(title: "Handshake", value: connectionDiagnostics.handshakeState)
                    row(title: "Authentication", value: connectionDiagnostics.authState)
                    row(title: "Session", value: connectionDiagnostics.sessionState)
                    if !connectionDiagnostics.localPath.isEmpty {
                        row(title: "Local Route", value: connectionDiagnostics.localPath)
                    }
                }

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

                Section(header: Text("Transport Layer")) {
                    row(title: "Transport State", value: transportDiagnostics.state.description)
                    row(title: "Messages Sent / Recv", value: "\(transportDiagnostics.messagesSent) / \(transportDiagnostics.messagesReceived)")
                    row(title: "Bytes Sent / Recv", value: "\(formatBytes(transportDiagnostics.bytesSent)) / \(formatBytes(transportDiagnostics.bytesReceived))")
                    row(title: "Round Trip Time (RTT)", value: "\(Int(metrics.rttMs)) ms")
                }

                Section(header: Text("Video Performance")) {
                    row(title: "Framerate", value: String(format: "%.1f FPS", metrics.currentFps))
                    row(title: "Bitrate", value: String(format: "%.1f Mbps", metrics.bitrateMbps))
                    row(title: "Codec", value: metrics.codec)
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

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return "\(bytes) B"
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
