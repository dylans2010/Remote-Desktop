import SwiftUI

/// Dedicated Host Active Session Interface for iOS.
public struct IOSHostSessionView: View {
    @ObservedObject var viewModel: IOSHostSessionViewModel
    @State private var pulseRecording: Bool = false

    public init(viewModel: IOSHostSessionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Live Session Hero Banner
                    VStack(spacing: 16) {
                        HStack(alignment: .center, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.18))
                                    .frame(width: 44, height: 44)

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
                                HStack(spacing: 6) {
                                    Text("Screen Broadcast Active")
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text("LIVE")
                                        .font(.system(size: 10, weight: .black))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                }

                                Text("Streaming this device to remote controller")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }

                        Divider()

                        // Stats Row
                        HStack(spacing: 16) {
                            HStack(spacing: 6) {
                                Image(systemName: "macbook")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text(viewModel.peerName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }

                            Spacer()

                            HStack(spacing: 5) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(viewModel.formattedDuration)
                                    .font(.subheadline.monospacedDigit().weight(.bold))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.red.opacity(0.25), lineWidth: 1.2)
                            )
                    )
                    .padding(.horizontal)
                    .padding(.top, 4)

                    // Session Permissions Card
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Active Session Permissions", systemImage: "slider.horizontal.3")
                            .font(.headline)
                            .foregroundColor(.primary)

                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "display")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Screen Viewing")
                                        .font(.subheadline.weight(.medium))
                                    Text("Live display frames are streamed")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: $viewModel.permissions.viewScreen)
                                    .disabled(true)
                                    .labelsHidden()
                            }

                            Divider()

                            HStack(spacing: 12) {
                                Image(systemName: "pencil.tip.crop.circle.badge.plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.purple)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Annotations & Drawing")
                                        .font(.subheadline.weight(.medium))
                                    Text("Allow peer to draw on your screen")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: $viewModel.permissions.annotation)
                                    .labelsHidden()
                                    .onChange(of: viewModel.permissions.annotation) { _, newValue in
                                        viewModel.syncPermissions()
                                        ToastManager.shared.showInfo(
                                            title: "Annotations \(newValue ? "Enabled" : "Disabled")",
                                            message: "Remote drawing access updated."
                                        )
                                    }
                            }

                            Divider()

                            HStack(spacing: 12) {
                                Image(systemName: "doc.on.clipboard.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Clipboard Sync")
                                        .font(.subheadline.weight(.medium))
                                    Text("Share clipboard with controller")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: $viewModel.permissions.clipboard)
                                    .labelsHidden()
                                    .onChange(of: viewModel.permissions.clipboard) { _, newValue in
                                        viewModel.syncPermissions()
                                        ToastManager.shared.showInfo(
                                            title: "Clipboard Sync \(newValue ? "Enabled" : "Disabled")",
                                            message: "Clipboard access updated."
                                        )
                                    }
                            }
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal)

                    Spacer(minLength: 20)

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            viewModel.showDiagnostics = true
                        } label: {
                            Label("Session Pipeline Diagnostics", systemImage: "chart.bar.xaxis")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .foregroundColor(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                        }

                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            viewModel.stopSession()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "stop.circle.fill")
                                Text("Stop Sharing Screen")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                LinearGradient(
                                    colors: [Color.red, Color(red: 0.85, green: 0.15, blue: 0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.red.opacity(0.35), radius: 8, x: 0, y: 4)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .padding(.vertical, 10)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Host Mode")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                pulseRecording = true
            }
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
