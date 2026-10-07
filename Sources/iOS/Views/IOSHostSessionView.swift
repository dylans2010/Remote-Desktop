import SwiftUI

/// Dedicated Host Active Session Interface for iOS.
public struct IOSHostSessionView: View {
    @ObservedObject var viewModel: IOSHostSessionViewModel

    public init(viewModel: IOSHostSessionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Live session banner
                HStack(spacing: 16) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen Sharing Active")
                            .font(.headline)
                        Text("Connected to \(viewModel.peerName) (\(viewModel.formattedDuration))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                // Permissions List
                VStack(alignment: .leading, spacing: 12) {
                    Text("Session Permissions")
                        .font(.headline)

                    Toggle("Screen Viewing", isOn: $viewModel.permissions.viewScreen)
                        .disabled(true)

                    Toggle("Annotations", isOn: $viewModel.permissions.annotation)
                        .onChange(of: viewModel.permissions.annotation) { _, _ in
                            viewModel.syncPermissions()
                        }

                    Toggle("Clipboard Sync", isOn: $viewModel.permissions.clipboard)
                        .onChange(of: viewModel.permissions.clipboard) { _, _ in
                            viewModel.syncPermissions()
                        }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                Spacer()

                Button(action: { viewModel.showDiagnostics = true }) {
                    Label("View Diagnostics", systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: { viewModel.stopSession() }) {
                    Text("Stop Session")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Host Mode")
            .sheet(isPresented: $viewModel.showDiagnostics) {
                IOSDiagnosticsView(
                    metrics: viewModel.healthMetrics,
                    permissions: viewModel.permissions,
                    peerName: viewModel.peerName,
                    isHost: true
                )
            }
        }
    }
}

public final class IOSHostSessionViewModel: ObservableObject, RemoteSessionDelegate, @unchecked Sendable {
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
        startTimer()
    }

    deinit {
        durationTimer?.invalidate()
    }

    public func syncPermissions() {
        RemoteSessionManager.shared.updateSessionPermissions(permissions)
    }

    public func stopSession() {
        durationTimer?.invalidate()
        RemoteSessionManager.shared.endSession(reason: "Host stopped session")
        DispatchQueue.main.async { [weak self] in
            self?.onSessionStopped?()
        }
    }

    private func startTimer() {
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
        DispatchQueue.main.async { self.permissions = permissions }
    }

    public func remoteSession(_ session: RemoteSessionManager, didUpdateHealth metrics: MediaHealthMetrics) {
        DispatchQueue.main.async { self.healthMetrics = metrics }
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
