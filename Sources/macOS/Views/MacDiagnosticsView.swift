import SwiftUI

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

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session Diagnostics")
                        .font(.title2)
                        .bold()
                    Text("Connection with \(peerName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    // Developer Connection Diagnostics (Requirement 13)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Connection Diagnostics")
                                .font(.headline)
                            Spacer()
                            Text("DEVELOPER TELEMETRY")
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
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .cornerRadius(8)

                    // Pipeline Diagnostic Assessment Banner
                    let diagnosticStage = metrics.diagnosePipeline(isHost: isHost)
                    HStack(spacing: 12) {
                        Image(systemName: diagnosticStage == .healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(diagnosticStage == .healthy ? .green : .orange)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(diagnosticStage == .healthy ? "Media Pipeline Healthy" : "Pipeline Attention Needed")
                                .font(.headline)
                            Text(diagnosticStage.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Transport Layer Diagnostics (Requirement 16)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transport Lifecycle Diagnostics")
                            .font(.headline)

                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                            GridRow {
                                metricItem(title: "Transport State", value: transportDiagnostics.state.description)
                                metricItem(title: "Messages Sent / Recv", value: "\(transportDiagnostics.messagesSent) / \(transportDiagnostics.messagesReceived)")
                            }
                            GridRow {
                                metricItem(title: "Bytes Sent / Recv", value: "\(formatBytes(transportDiagnostics.bytesSent)) / \(formatBytes(transportDiagnostics.bytesReceived))")
                                metricItem(title: "Round Trip Time (RTT)", value: "\(Int(metrics.rttMs)) ms")
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(8)

            // Media Metrics Grid
            VStack(alignment: .leading, spacing: 8) {
                Text("Media Stream Telemetry")
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
                        metricItem(title: "Security & Encryption", value: "Curve25519 Encrypted")
                    }
                }
            }

            Divider()

            // Active permissions summary
            VStack(alignment: .leading, spacing: 8) {
                Text("Session Permissions")
                    .font(.headline)

                HStack(spacing: 12) {
                    permPill(title: "Viewing", allowed: permissions.viewScreen)
                    permPill(title: "Mouse", allowed: permissions.mouse)
                    permPill(title: "Keyboard", allowed: permissions.keyboard)
                    permPill(title: "Annotations", allowed: permissions.annotation)
                    permPill(title: "Clipboard", allowed: permissions.clipboard)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 4)
    }

    Spacer(minLength: 0)
}
.padding(20)
.frame(width: 560, height: 620)
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
                .font(.caption)
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
            Text(title)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(allowed ? Color.green.opacity(0.12) : Color.gray.opacity(0.12))
        .cornerRadius(6)
    }
}
