import SwiftUI
import AppKit

/// Advanced connection and media pipeline diagnostics modal.
public struct MacDiagnosticsView: View {
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

    private var diagnosticStage: PipelineDiagnosticStage {
        metrics.diagnosePipeline(isHost: isHost)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Session Telemetry & Diagnostics")
                            .font(.title3.weight(.bold))
                        Text("Active link with \(peerName) (\(isHost ? "Host" : "Controller"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    // Pipeline Status Banner
                    HStack(spacing: 12) {
                        Image(systemName: diagnosticStage == .healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(diagnosticStage == .healthy ? .green : .orange)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(diagnosticStage == .healthy ? "Media Pipeline Operating Normally" : "Pipeline Attention Needed")
                                .font(.headline)
                            Text(diagnosticStage.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(diagnosticStage == .healthy ? "OPTIMAL" : "DEGRADED")
                            .font(.system(size: 10, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(diagnosticStage == .healthy ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                            .foregroundColor(diagnosticStage == .healthy ? .green : .orange)
                            .clipShape(Capsule())
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(diagnosticStage == .healthy ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )

                    // Quick Metric Highlights (4 Cards)
                    HStack(spacing: 10) {
                        MacMetricCard(icon: "gauge.with.needle.fill", color: .green, title: "RTT Latency", value: "\(Int(metrics.rttMs)) ms")
                        MacMetricCard(icon: "film.stack.fill", color: .blue, title: "Framerate", value: String(format: "%.1f FPS", metrics.currentFps))
                        MacMetricCard(icon: "waveform.path.ecg", color: .purple, title: "Bitrate", value: String(format: "%.1f Mbps", metrics.bitrateMbps))
                        MacMetricCard(icon: "antenna.radiowaves.left.and.right.slash", color: metrics.packetLossPercent > 2.0 ? .red : .teal, title: "Packet Loss", value: String(format: "%.1f%%", metrics.packetLossPercent))
                    }

                    // Developer Connection Diagnostics
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Connection Link & Identity", systemImage: "network")
                                .font(.headline)
                            Spacer()
                            Text("TELEMETRY")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }

                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                            GridRow {
                                metricItem(title: "Peer", value: connectionDiagnostics.peerName)
                                metricItem(title: "Device Identity", value: connectionDiagnostics.deviceIdentityStatus)
                            }
                            GridRow {
                                metricItem(title: "Pairing", value: connectionDiagnostics.pairingStatus)
                                metricItem(title: "Endpoint", value: connectionDiagnostics.endpoint)
                            }
                            GridRow {
                                metricItem(title: "Endpoint Source", value: connectionDiagnostics.endpointSource)
                                metricItem(title: "Reachability", value: connectionDiagnostics.reachability)
                            }
                            GridRow {
                                metricItem(title: "Transport", value: connectionDiagnostics.transportState)
                                metricItem(title: "Handshake", value: connectionDiagnostics.handshakeState)
                            }
                            GridRow {
                                metricItem(title: "Authentication", value: connectionDiagnostics.authState)
                                metricItem(title: "Session", value: connectionDiagnostics.sessionState)
                            }
                        }

                        if !connectionDiagnostics.localPath.isEmpty {
                            Text("Local Route: \(connectionDiagnostics.localPath)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                    // Transport Layer Diagnostics
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Transport Layer", systemImage: "cable.connector")
                            .font(.headline)

                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                            GridRow {
                                metricItem(title: "Transport State", value: transportDiagnostics.state.description)
                                metricItem(title: "Packets (Sent / Recv)", value: "\(transportDiagnostics.messagesSent) / \(transportDiagnostics.messagesReceived)")
                            }
                            GridRow {
                                metricItem(title: "Bytes (Sent / Recv)", value: "\(formatBytes(transportDiagnostics.bytesSent)) / \(formatBytes(transportDiagnostics.bytesReceived))")
                                metricItem(title: "Round Trip Time (RTT)", value: "\(Int(metrics.rttMs)) ms")
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                    // Media Metrics
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Video Pipeline Delivery", systemImage: "video.fill")
                            .font(.headline)

                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                            GridRow {
                                metricItem(title: "Framerate", value: String(format: "%.1f FPS", metrics.currentFps))
                                metricItem(title: "Bitrate", value: String(format: "%.1f Mbps", metrics.bitrateMbps))
                            }

                            if isHost {
                                GridRow {
                                    metricItem(title: "Frames Captured", value: "\(metrics.framesCaptured)")
                                    metricItem(title: "Frames Encoded", value: "\(metrics.framesEncoded)")
                                }
                                GridRow {
                                    metricItem(title: "Frames Sent", value: "\(metrics.framesSent)")
                                    metricItem(title: "Codec", value: metrics.codec)
                                }
                            } else {
                                GridRow {
                                    metricItem(title: "Frames Received", value: "\(metrics.framesReceived)")
                                    metricItem(title: "Frames Decoded", value: "\(metrics.framesDecoded)")
                                }
                                GridRow {
                                    metricItem(title: "Frames Rendered", value: "\(metrics.framesRendered)")
                                    metricItem(title: "Packet Loss", value: String(format: "%.1f%%", metrics.packetLossPercent))
                                }
                            }

                            GridRow {
                                metricItem(title: "Resolution", value: metrics.activeResolution)
                                metricItem(title: "Security & Encryption", value: "Curve25519 + AES-GCM")
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                    // Active Permissions Summary
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Active Session Permissions", systemImage: "slider.horizontal.3")
                            .font(.headline)

                        HStack(spacing: 8) {
                            permPill(title: "Viewing", allowed: permissions.viewScreen)
                            permPill(title: "Mouse", allowed: permissions.mouse)
                            permPill(title: "Keyboard", allowed: permissions.keyboard)
                            permPill(title: "Annotations", allowed: permissions.annotation)
                            permPill(title: "Clipboard", allowed: permissions.clipboard)
                            permPill(title: "File Transfer", allowed: permissions.fileTransfer)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                    // Copy Report Action
                    Button {
                        copyReport()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Copy Diagnostics Report to Clipboard", systemImage: "doc.on.doc.fill")
                                .font(.caption.weight(.semibold))
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(width: 580, height: 640)
    }

    private func copyReport() {
        let text = """
        === Remote Desktop macOS Diagnostics ===
        Peer: \(peerName)
        Role: \(isHost ? "Host" : "Controller")
        Pipeline Assessment: \(diagnosticStage.rawValue)
        RTT Latency: \(Int(metrics.rttMs)) ms
        Framerate: \(String(format: "%.1f FPS", metrics.currentFps))
        Bitrate: \(String(format: "%.1f Mbps", metrics.bitrateMbps))
        Packet Loss: \(String(format: "%.1f%%", metrics.packetLossPercent))
        Codec: \(metrics.codec)
        Transport: \(connectionDiagnostics.transportState)
        Auth: \(connectionDiagnostics.authState)
        Endpoint: \(connectionDiagnostics.endpoint)
        Bytes: Sent \(formatBytes(transportDiagnostics.bytesSent)), Recv \(formatBytes(transportDiagnostics.bytesReceived))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        MacToastManager.shared.showSuccess(title: "Report Copied", message: "Telemetry copied to clipboard.")
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

    private func metricItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .bold()
        }
    }

    private func permPill(title: String, allowed: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(allowed ? .green : .secondary)
                .font(.caption2)
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(allowed ? Color.green.opacity(0.12) : Color.gray.opacity(0.12))
        .cornerRadius(6)
    }
}

private struct MacMetricCard: View {
    let icon: String
    let color: Color
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption2.weight(.bold))
                Spacer()
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
