import SwiftUI
import UIKit

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

    private var assessmentStage: PipelineDiagnosticStage {
        metrics.diagnosePipeline(isHost: isHost)
    }

    public var body: some View {
        NavigationStack {
            List {
                // Pipeline Health Banner Card
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(assessmentStage == .healthy ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                                .frame(width: 44, height: 44)

                            Image(systemName: assessmentStage == .healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(assessmentStage == .healthy ? .green : .orange)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(assessmentStage == .healthy ? "Pipeline Operating Normally" : "Pipeline Attention Needed")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text(assessmentStage.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Status Overview", systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }

                // Quick Performance Highlights (Grid)
                Section {
                    HStack(spacing: 12) {
                        DiagnosticMetricCard(
                            icon: "gauge.with.needle.fill",
                            color: .green,
                            title: "RTT Latency",
                            value: "\(Int(metrics.rttMs)) ms"
                        )

                        DiagnosticMetricCard(
                            icon: "film.stack.fill",
                            color: .blue,
                            title: "Framerate",
                            value: String(format: "%.1f FPS", metrics.currentFps)
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)

                    HStack(spacing: 12) {
                        DiagnosticMetricCard(
                            icon: "waveform.path.ecg",
                            color: .purple,
                            title: "Bitrate",
                            value: String(format: "%.1f Mbps", metrics.bitrateMbps)
                        )

                        DiagnosticMetricCard(
                            icon: "antenna.radiowaves.left.and.right.slash",
                            color: metrics.packetLossPercent > 2.0 ? .red : .teal,
                            title: "Packet Loss",
                            value: String(format: "%.1f%%", metrics.packetLossPercent)
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Label("Performance Metrics", systemImage: "speedometer")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }

                // Connection Diagnostics
                Section {
                    row(icon: "person.circle", title: "Peer", value: connectionDiagnostics.peerName)
                    row(icon: "shield.lefthalf.filled", title: "Device Identity", value: connectionDiagnostics.deviceIdentityStatus)
                    row(icon: "link", title: "Pairing", value: connectionDiagnostics.pairingStatus)
                    row(icon: "mappin.and.ellipse", title: "Endpoint", value: connectionDiagnostics.endpoint)
                    row(icon: "network", title: "Endpoint Source", value: connectionDiagnostics.endpointSource)
                    row(icon: "waveform", title: "Reachability", value: connectionDiagnostics.reachability)
                    row(icon: "cable.connector", title: "Transport", value: connectionDiagnostics.transportState)
                    row(icon: "handshake", title: "Handshake", value: connectionDiagnostics.handshakeState)
                    row(icon: "lock.shield", title: "Authentication", value: connectionDiagnostics.authState)
                    row(icon: "circle.circle", title: "Session", value: connectionDiagnostics.sessionState)
                    if !connectionDiagnostics.localPath.isEmpty {
                        row(icon: "point.topleft.down.curvedto.point.bottomright.up", title: "Local Route", value: connectionDiagnostics.localPath)
                    }
                } header: {
                    Label("Connection Link", systemImage: "network")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }

                // Transport Layer
                Section {
                    row(icon: "waveform.badge.magnifyingglass", title: "Transport State", value: transportDiagnostics.state.description)
                    row(icon: "arrow.up.arrow.down", title: "Packets (Sent / Recv)", value: "\(transportDiagnostics.messagesSent) / \(transportDiagnostics.messagesReceived)")
                    row(icon: "arrow.up.arrow.down.circle", title: "Data (Sent / Recv)", value: "\(formatBytes(transportDiagnostics.bytesSent)) / \(formatBytes(transportDiagnostics.bytesReceived))")
                    row(icon: "clock.arrow.2.circlepath", title: "Round Trip Time (RTT)", value: "\(Int(metrics.rttMs)) ms")
                } header: {
                    Label("Transport Layer", systemImage: "cable.connector")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }

                // Video Pipeline
                Section {
                    row(icon: "film", title: "Video Codec", value: metrics.codec)
                    if isHost {
                        row(icon: "camera", title: "Frames Captured", value: "\(metrics.framesCaptured)")
                        row(icon: "cpu", title: "Frames Encoded", value: "\(metrics.framesEncoded)")
                        row(icon: "arrow.up.circle", title: "Frames Sent", value: "\(metrics.framesSent)")
                    } else {
                        row(icon: "arrow.down.circle", title: "Frames Received", value: "\(metrics.framesReceived)")
                        row(icon: "cpu", title: "Frames Decoded", value: "\(metrics.framesDecoded)")
                        row(icon: "display", title: "Frames Rendered", value: "\(metrics.framesRendered)")
                    }
                } header: {
                    Label("Video Encoding & Delivery", systemImage: "video.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }

                // Active Permissions
                Section {
                    permissionRow(icon: "display", title: "Screen Viewing", allowed: permissions.viewScreen)
                    permissionRow(icon: "hand.tap", title: "Remote Control", allowed: permissions.controlScreen)
                    permissionRow(icon: "pencil.tip.crop.circle", title: "Drawing / Annotations", allowed: permissions.annotation)
                    permissionRow(icon: "doc.on.clipboard", title: "Clipboard Sync", allowed: permissions.clipboard)
                } header: {
                    Label("Active Session Permissions", systemImage: "slider.horizontal.3")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }

                // Copy Diagnostics Action
                Section {
                    Button {
                        copyDiagnostics()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Copy Diagnostics Report", systemImage: "doc.on.doc.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.blue)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func copyDiagnostics() {
        let text = """
        === Remote Desktop Diagnostics ===
        Peer: \(peerName)
        Role: \(isHost ? "Host" : "Controller")
        Pipeline Assessment: \(assessmentStage.rawValue)
        RTT: \(Int(metrics.rttMs)) ms
        Framerate: \(String(format: "%.1f FPS", metrics.currentFps))
        Bitrate: \(String(format: "%.1f Mbps", metrics.bitrateMbps))
        Packet Loss: \(String(format: "%.1f%%", metrics.packetLossPercent))
        Codec: \(metrics.codec)
        Transport: \(connectionDiagnostics.transportState)
        Auth: \(connectionDiagnostics.authState)
        Endpoint: \(connectionDiagnostics.endpoint)
        Bytes: Sent \(formatBytes(transportDiagnostics.bytesSent)), Recv \(formatBytes(transportDiagnostics.bytesReceived))
        """
        UIPasteboard.general.string = text
        ToastManager.shared.showSuccess(title: "Report Copied", message: "Diagnostics copied to clipboard.")
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

    private func row(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(title)
                .font(.subheadline)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
        }
    }

    private func permissionRow(icon: String, title: String, allowed: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(title)
                .font(.subheadline)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(allowed ? .green : .secondary)
                    .font(.caption)
                Text(allowed ? "Allowed" : "Denied")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(allowed ? .green : .secondary)
            }
        }
    }
}

private struct DiagnosticMetricCard: View {
    let icon: String
    let color: Color
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption.weight(.bold))
                Spacer()
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
