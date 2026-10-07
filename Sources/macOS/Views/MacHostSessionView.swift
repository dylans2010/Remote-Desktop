import SwiftUI

/// Dedicated Host Session Management Interface for the Mac being viewed or controlled.
public struct MacHostSessionView: View {
    @ObservedObject var viewModel: MacHostSessionViewModel

    public init(viewModel: MacHostSessionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Prominent Active Session Header
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 48, height: 48)
                    Circle()
                        .fill(Color.green)
                        .frame(width: 16, height: 16)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Active Remote Session")
                            .font(.title2)
                            .bold()
                        Text("● LIVE")
                            .font(.caption2)
                            .bold()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }

                    Text("Connected to \(viewModel.peerName) for \(viewModel.formattedDuration)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { viewModel.showDiagnostics = true }) {
                    Label("Diagnostics", systemImage: "chart.bar.xaxis")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            // Permissions Control Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Session Permissions")
                        .font(.headline)
                    Spacer()
                    Text("Changes take effect immediately")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Presets selector
                HStack(spacing: 8) {
                    ForEach(SessionPreset.allCases) { preset in
                        Button(preset.rawValue) {
                            viewModel.applyPreset(preset)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Divider()

                // Granular toggles
                VStack(spacing: 12) {
                    permissionToggle(
                        title: "Screen Viewing",
                        subtitle: "Remote peer can see this Mac's display",
                        systemImage: "eye.fill",
                        isOn: $viewModel.permissions.viewScreen,
                        disabled: true
                    )

                    permissionToggle(
                        title: "Mouse Control",
                        subtitle: "Remote peer can move cursor and click",
                        systemImage: "cursorarrow.rays",
                        isOn: $viewModel.permissions.mouse
                    )

                    permissionToggle(
                        title: "Keyboard Control",
                        subtitle: "Remote peer can type and send keystrokes",
                        systemImage: "keyboard",
                        isOn: $viewModel.permissions.keyboard
                    )

                    permissionToggle(
                        title: "Drawing & Annotations",
                        subtitle: "Remote peer can draw visual indicators on screen",
                        systemImage: "pencil.tip",
                        isOn: $viewModel.permissions.annotation
                    )

                    permissionToggle(
                        title: "Clipboard Sync",
                        subtitle: "Synchronize text and images copied between machines",
                        systemImage: "doc.on.clipboard",
                        isOn: $viewModel.permissions.clipboard
                    )

                    permissionToggle(
                        title: "File Transfer",
                        subtitle: "Allow receiving files from remote peer",
                        systemImage: "folder.badge.gearshape",
                        isOn: $viewModel.permissions.fileTransfer
                    )
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            Spacer()

            // Authoritative Stop Session Button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("End Remote Control")
                        .font(.headline)
                    Text("Immediately terminates video stream and revokes all remote control.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { viewModel.stopSession() }) {
                    Label("Stop Session", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.red.opacity(0.08))
            .cornerRadius(12)
        }
        .padding(24)
        .sheet(isPresented: $viewModel.showDiagnostics) {
            MacDiagnosticsView(
                metrics: viewModel.healthMetrics,
                permissions: viewModel.permissions,
                peerName: viewModel.peerName,
                isHost: true
            )
        }
    }

    private func permissionToggle(title: String, subtitle: String, systemImage: String, isOn: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(isOn.wrappedValue ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .bold()
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .disabled(disabled)
                .onChange(of: isOn.wrappedValue) { _, _ in
                    viewModel.syncPermissionsToSession()
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
