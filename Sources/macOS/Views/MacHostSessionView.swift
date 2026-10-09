import SwiftUI

/// Dedicated Host Session Management Interface for the Mac being viewed or controlled.
public struct MacHostSessionView: View {
    @ObservedObject var viewModel: MacHostSessionViewModel
    @State private var pulseRecording: Bool = false

    public init(viewModel: MacHostSessionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Prominent Active Session Header Banner
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.18))
                            .frame(width: 48, height: 48)

                        Circle()
                            .fill(Color.red)
                            .frame(width: 14, height: 14)
                            .scaleEffect(pulseRecording ? 1.25 : 0.9)
                            .animation(
                                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                value: pulseRecording
                            )
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Active Remote Screen Broadcast")
                                .font(.title3.weight(.bold))

                            Text("LIVE")
                                .font(.system(size: 10, weight: .black))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }

                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "macbook.and.iphone")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text("Controller: \(viewModel.peerName)")
                                    .font(.subheadline.weight(.semibold))
                            }

                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(viewModel.formattedDuration)
                                    .font(.subheadline.monospacedDigit().weight(.bold))
                            }
                        }
                    }

                    Spacer()

                    Button {
                        viewModel.showDiagnostics = true
                    } label: {
                        Label("Diagnostics", systemImage: "chart.bar.xaxis")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.red.opacity(0.25), lineWidth: 1.2)
                        )
                )

                // Permissions Control Section
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Session Permissions", systemImage: "slider.horizontal.3")
                            .font(.headline)
                        Spacer()
                        Text("Changes take effect immediately")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Presets selector
                    HStack(spacing: 8) {
                        Text("Quick Presets:")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        ForEach(SessionPreset.allCases) { preset in
                            Button(preset.rawValue) {
                                viewModel.applyPreset(preset)
                                MacToastManager.shared.showInfo(
                                    title: "Preset Applied",
                                    message: "\(preset.rawValue) permissions configured."
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Divider()

                    // Granular toggles
                    VStack(spacing: 12) {
                        MacHostPermissionToggle(
                            title: "Screen Viewing",
                            subtitle: "Remote peer can see this Mac's display",
                            icon: "display",
                            color: .blue,
                            isOn: $viewModel.permissions.viewScreen,
                            disabled: true
                        )

                        MacHostPermissionToggle(
                            title: "Mouse Control",
                            subtitle: "Remote peer can move cursor and click",
                            icon: "cursorarrow.rays",
                            color: .green,
                            isOn: $viewModel.permissions.mouse,
                            onChange: {
                                viewModel.syncPermissionsToSession()
                            }
                        )

                        MacHostPermissionToggle(
                            title: "Keyboard Control",
                            subtitle: "Remote peer can type and send keystrokes",
                            icon: "keyboard",
                            color: .indigo,
                            isOn: $viewModel.permissions.keyboard,
                            onChange: {
                                viewModel.syncPermissionsToSession()
                            }
                        )

                        MacHostPermissionToggle(
                            title: "Drawing & Annotations",
                            subtitle: "Remote peer can draw visual indicators on screen",
                            icon: "pencil.tip.crop.circle.badge.plus",
                            color: .purple,
                            isOn: $viewModel.permissions.annotation,
                            onChange: {
                                viewModel.syncPermissionsToSession()
                            }
                        )

                        MacHostPermissionToggle(
                            title: "Clipboard Sync",
                            subtitle: "Synchronize text and images copied between machines",
                            icon: "doc.on.clipboard.fill",
                            color: .orange,
                            isOn: $viewModel.permissions.clipboard,
                            onChange: {
                                viewModel.syncPermissionsToSession()
                            }
                        )

                        MacHostPermissionToggle(
                            title: "File Transfer",
                            subtitle: "Allow receiving files from remote peer",
                            icon: "folder.badge.gearshape",
                            color: .teal,
                            isOn: $viewModel.permissions.fileTransfer,
                            onChange: {
                                viewModel.syncPermissionsToSession()
                            }
                        )
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                // Authoritative Stop Session Card
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("End Remote Screen Broadcast")
                            .font(.headline)
                        Text("Immediately terminates video stream and revokes all remote control access.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        viewModel.stopSession()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.circle.fill")
                            Text("Stop Session")
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [Color.red, Color(red: 0.85, green: 0.15, blue: 0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: Color.red.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.red.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .padding(24)
        }
        .onAppear {
            pulseRecording = true
        }
        .sheet(isPresented: $viewModel.showDiagnostics) {
            MacDiagnosticsView(
                metrics: viewModel.healthMetrics,
                permissions: viewModel.permissions,
                peerName: viewModel.peerName,
                isHost: true
            )
        }
    }
}

private struct MacHostPermissionToggle: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    @Binding var isOn: Bool
    var disabled: Bool = false
    var onChange: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .disabled(disabled)
                .onChange(of: isOn) { _, _ in
                    onChange?()
                }
        }
    }
}

/// ViewModel for Host session management.
public final class MacHostSessionViewModel: ObservableObject, RemoteSessionDelegate, @unchecked Sendable {
    @Published public var peerName: String
    @Published public var permissions: RemoteSessionPermissions
    @Published public var formattedDuration: String = "0:00"
    @Published public var healthMetrics: MediaHealthMetrics = MediaHealthMetrics()
    @Published public var showDiagnostics: Bool = false

    private var durationTimer: Timer?
    private var startTime: Date = Date()
    public var onSessionStopped: (() -> Void)?

    public init(peerName: String, initialPermissions: RemoteSessionPermissions) {
        self.peerName = peerName
        self.permissions = initialPermissions
        RemoteSessionManager.shared.delegate = self
        self.startTime = RemoteSessionManager.shared.sessionStartTime ?? Date()
        startDurationTimer()
        HostModeManager.shared.updateStatusItem(peerName: peerName, permissions: initialPermissions)
    }

    deinit {
        durationTimer?.invalidate()
    }

    public func applyPreset(_ preset: SessionPreset) {
        self.permissions = preset.permissions
        syncPermissionsToSession()
    }

    public func syncPermissionsToSession() {
        if permissions.mouse || permissions.keyboard {
            permissions.controlScreen = true
        } else {
            permissions.controlScreen = false
        }
        RemoteSessionManager.shared.updateSessionPermissions(permissions)
        HostModeManager.shared.updateStatusItem(peerName: peerName, permissions: permissions)
    }

    public func stopSession() {
        durationTimer?.invalidate()
        HostModeManager.shared.updateStatusItem(peerName: nil, permissions: nil)
        RemoteSessionManager.shared.endSession(reason: "Host ended session")
        DispatchQueue.main.async { [weak self] in
            self?.onSessionStopped?()
        }
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let elapsed = Int(Date().timeIntervalSince(self.startTime))
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            DispatchQueue.main.async {
                self.formattedDuration = String(format: "%d:%02d", minutes, seconds)
                self.healthMetrics = RemoteMediaSession.shared.getHealthMetrics()
            }
        }
    }

    // MARK: - RemoteSessionDelegate

    public func remoteSession(_ session: RemoteSessionManager, didChangeState state: SessionState) {
        if state == .disconnected || state.isTerminal {
            DispatchQueue.main.async { [weak self] in
                self?.durationTimer?.invalidate()
                self?.onSessionStopped?()
            }
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didReceiveFrame frameData: Data, timestamp: Double) {}

    public func remoteSession(_ session: RemoteSessionManager, didUpdatePermissions permissions: RemoteSessionPermissions) {
        DispatchQueue.main.async {
            self.permissions = permissions
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didUpdateHealth metrics: MediaHealthMetrics) {
        DispatchQueue.main.async {
            self.healthMetrics = metrics
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didReceiveAnnotation stroke: AnnotationStroke, action: AnnotationAction) {}

    public func remoteSession(_ session: RemoteSessionManager, didEncounterError error: Error) {}

    public func remoteSessionDidEnd(_ session: RemoteSessionManager, reason: String, endedByHost: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.durationTimer?.invalidate()
            self?.onSessionStopped?()
        }
    }
}
