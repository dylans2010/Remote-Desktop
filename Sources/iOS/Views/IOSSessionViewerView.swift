import SwiftUI
import UIKit

public struct IOSSessionViewerView: View {
    @ObservedObject var viewModel: IOSSessionViewModel
    @State private var annotationTool: AnnotationTool = .freehand
    @State private var isAnnotationModeActive: Bool = false
    @State private var activePoints: [NormalizedPoint] = []
    @State private var activeStrokeId: UUID = UUID()

    public init(viewModel: IOSSessionViewModel) {
        self.viewModel = viewModel
    }

    private var latencyColor: Color {
        if viewModel.latencyMs <= 0 {
            return .gray
        } else if viewModel.latencyMs < 45 {
            return .green
        } else if viewModel.latencyMs < 90 {
            return .orange
        } else {
            return .red
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Glass Floating HUD Header
            HStack(spacing: 12) {
                // Peer Name & Platform Pill
                HStack(spacing: 8) {
                    Image(systemName: "macbook")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.peerName)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            // Latency Pill
                            HStack(spacing: 3) {
                                Image(systemName: "gauge.with.needle.fill")
                                    .font(.system(size: 9))
                                Text("\(Int(viewModel.latencyMs)) ms")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .foregroundColor(latencyColor)

                            // Route Badge
                            HStack(spacing: 3) {
                                Image(systemName: viewModel.isRelayed ? "arrow.triangle.swap" : "bolt.shield.fill")
                                    .font(.system(size: 8))
                                Text(viewModel.isRelayed ? "Relay" : "Direct P2P")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(viewModel.isRelayed ? Color.orange.opacity(0.85) : Color.green.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                // Actions Group
                HStack(spacing: 10) {
                    if viewModel.connectionState == .connected && viewModel.permissions.annotation {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isAnnotationModeActive.toggle()
                            }
                            if isAnnotationModeActive {
                                ToastManager.shared.showInfo(title: "Annotation Mode", message: "Draw on the screen to collaborate.")
                            }
                        } label: {
                            Image(systemName: isAnnotationModeActive ? "pencil.tip.crop.circle.badge.plus.fill" : "pencil.tip")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isAnnotationModeActive ? .yellow : .white)
                                .padding(8)
                                .background(isAnnotationModeActive ? Color.yellow.opacity(0.25) : Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.showDiagnostics = true
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.disconnect()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                            Text(viewModel.isErrorState ? "Close" : "Disconnect")
                                .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Color.black.opacity(0.92)
                    .overlay(
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 1),
                        alignment: .bottom
                    )
            )

            // High Latency Alert Banner (if latency exceeds 120ms during connection)
            if viewModel.connectionState == .connected && viewModel.latencyMs > 120 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.orange)
                    Text("High network latency (\(Int(viewModel.latencyMs)) ms) • Video quality dynamically adapted")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.25))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Remote Screen Viewport
            GeometryReader { geometry in
                ZStack {
                    Color.black

                    if let image = viewModel.currentFrameImage, viewModel.connectionState == .connected {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        guard !isAnnotationModeActive else { return }
                                        guard viewModel.permissions.mouse else { return }
                                        let normX = value.location.x / geometry.size.width
                                        let normY = value.location.y / geometry.size.height
                                        viewModel.sendRemoteInput(type: .mouseMove, x: normX, y: normY)
                                    }
                            )

                        // Annotation Overlay Canvas
                        Canvas { context, size in
                            for stroke in viewModel.annotationStrokes {
                                drawStroke(stroke, in: &context, size: size)
                            }
                            if !activePoints.isEmpty {
                                let activeStroke = AnnotationStroke(
                                    id: activeStrokeId,
                                    tool: annotationTool,
                                    colorHex: "#FF3B30",
                                    lineWidth: 4.0,
                                    points: activePoints
                                )
                                drawStroke(activeStroke, in: &context, size: size)
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard isAnnotationModeActive && viewModel.permissions.annotation else { return }
                                    let normPoint = NormalizedPoint(
                                        x: value.location.x / geometry.size.width,
                                        y: value.location.y / geometry.size.height
                                    )
                                    activePoints.append(normPoint)
                                    viewModel.handleAnnotationAction(stroke: nil, action: .point, point: normPoint)
                                }
                                .onEnded { _ in
                                    guard isAnnotationModeActive && viewModel.permissions.annotation else { return }
                                    if !activePoints.isEmpty {
                                        let finalStroke = AnnotationStroke(
                                            id: activeStrokeId,
                                            tool: annotationTool,
                                            colorHex: "#FF3B30",
                                            lineWidth: 4.0,
                                            points: activePoints
                                        )
                                        viewModel.handleAnnotationAction(stroke: finalStroke, action: .end, point: nil)
                                        activePoints.removeAll()
                                        activeStrokeId = UUID()
                                    }
                                }
                        )
                    } else if viewModel.isErrorState {
                        // Actionable Error View with visual punch
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.15))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.red)
                            }

                            VStack(spacing: 8) {
                                Text(viewModel.connectionState.statusDescription)
                                    .font(.title3.weight(.bold))
                                    .foregroundColor(.white)

                                Text(viewModel.errorMessage ?? "The connection could not be established.")
                                    .font(.callout)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }

                            HStack(spacing: 14) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    viewModel.retryConnection()
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                }

                                Button {
                                    viewModel.disconnect()
                                } label: {
                                    Text("Return to Devices")
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color.white.opacity(0.15))
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(28)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .padding(24)
                    } else if viewModel.isStreamTimedOut {
                        // Blank Screen Detection Banner / Card
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 64, height: 64)
                                Image(systemName: "video.slash.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.orange)
                            }

                            VStack(spacing: 4) {
                                Text("Screen Stream Paused")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                Text("Connected to \(viewModel.peerName), but video frames have stalled.")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }

                            HStack(spacing: 14) {
                                Button {
                                    viewModel.retryStream()
                                } label: {
                                    Label("Resume Stream", systemImage: "play.fill")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                }

                                Button {
                                    viewModel.disconnect()
                                } label: {
                                    Text("Disconnect")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.15))
                                        .foregroundColor(.red)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                    } else {
                        // Connecting Progress View with modern pulsing visuals
                        VStack(spacing: 18) {
                            ZStack {
                                Circle()
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                    .frame(width: 64, height: 64)
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                    .scaleEffect(1.4)
                            }

                            VStack(spacing: 4) {
                                Text(viewModel.connectionState.statusDescription)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("Connecting to \(viewModel.peerName)...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            Button {
                                viewModel.disconnect()
                            } label: {
                                Text("Cancel")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.12))
                                    .foregroundColor(.red)
                                    .clipShape(Capsule())
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }

            // Annotation Palette Bar (Floating Dock)
            if isAnnotationModeActive && viewModel.permissions.annotation {
                HStack(spacing: 18) {
                    ForEach(AnnotationTool.allCases, id: \.self) { tool in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            annotationTool = tool
                        } label: {
                            Image(systemName: tool.systemImageName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(annotationTool == tool ? .yellow : .white)
                                .padding(8)
                                .background(annotationTool == tool ? Color.yellow.opacity(0.2) : Color.clear)
                                .clipShape(Circle())
                        }
                    }

                    Spacer()

                    Button {
                        if !viewModel.annotationStrokes.isEmpty {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.annotationStrokes.removeLast()
                            viewModel.handleAnnotationAction(stroke: nil, action: .undo, point: nil)
                        }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.annotationStrokes.removeAll()
                        viewModel.handleAnnotationAction(stroke: nil, action: .clear, point: nil)
                        ToastManager.shared.showInfo(title: "Annotations Cleared", message: nil)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.black.opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(Color.black)
            }
        }
        .sheet(isPresented: $viewModel.showDiagnostics) {
            IOSDiagnosticsView(
                metrics: viewModel.healthMetrics,
                permissions: viewModel.permissions,
                peerName: viewModel.peerName,
                isHost: false
            )
        }
    }

    private func drawStroke(_ stroke: AnnotationStroke, in context: inout GraphicsContext, size: CGSize) {
        guard !stroke.points.isEmpty else { return }
        var path = Path()
        let first = stroke.points[0].denormalized(width: size.width, height: size.height)
        path.move(to: first)
        for point in stroke.points.dropFirst() {
            let denorm = point.denormalized(width: size.width, height: size.height)
            path.addLine(to: denorm)
        }
        context.stroke(path, with: .color(.red), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round))
    }
}

public final class IOSSessionViewModel: ObservableObject, RemoteSessionDelegate, @unchecked Sendable {
    @Published public var peerName: String
    @Published public var targetDevice: Device?
    @Published public var connectionState: SessionState = .connecting
    @Published public var currentFrameImage: UIImage? = nil
    @Published public var latencyMs: Double = 0.0
    @Published public var isRelayed: Bool = false
    @Published public var permissions: RemoteSessionPermissions = .standardDefault
    @Published public var annotationStrokes: [AnnotationStroke] = []
    @Published public var healthMetrics: MediaHealthMetrics = MediaHealthMetrics()
    @Published public var isStreamTimedOut: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var showDiagnostics: Bool = false

    public var isErrorState: Bool {
        return connectionState.isTerminal && connectionState != .disconnected
    }

    public var onDisconnect: (() -> Void)?

    private var frameWatchdogTimer: Timer?
    private var lastFrameReceivedTime: Date?

    public init(peerName: String, targetDevice: Device? = nil) {
        self.peerName = peerName
        self.targetDevice = targetDevice
        self.connectionState = RemoteSessionManager.shared.currentState
        RemoteSessionManager.shared.delegate = self
        self.permissions = RemoteSessionManager.shared.activePermissions
        startFrameWatchdog()
    }

    deinit {
        frameWatchdogTimer?.invalidate()
    }

    private func startFrameWatchdog() {
        frameWatchdogTimer?.invalidate()
        lastFrameReceivedTime = Date()
        isStreamTimedOut = false

        frameWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.connectionState == .connected, self.currentFrameImage == nil, let lastTime = self.lastFrameReceivedTime {
                let elapsed = Date().timeIntervalSince(lastTime)
                if elapsed >= 5.0 {
                    DispatchQueue.main.async {
                        self.isStreamTimedOut = true
                        self.healthMetrics = RemoteMediaSession.shared.getHealthMetrics()
                    }
                }
            }
        }
    }

    public func retryStream() {
        DispatchQueue.main.async {
            self.isStreamTimedOut = false
            self.lastFrameReceivedTime = Date()
        }
    }

    public func retryConnection() {
        guard let device = targetDevice else { return }
        DispatchQueue.main.async {
            self.errorMessage = nil
            self.connectionState = .connecting
            self.isStreamTimedOut = false
            self.lastFrameReceivedTime = Date()
        }
        Task {
            do {
                try await RemoteSessionManager.shared.startSession(with: device, requestedPermissions: permissions)
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.connectionState = RemoteSessionManager.shared.currentState
                }
            }
        }
    }

    public func sendRemoteInput(type: RemoteInputEvent.InputType, x: Double, y: Double) {
        guard permissions.isInputAuthorized(for: type) else { return }
        let event = RemoteInputEvent(type: type, x: x, y: y)
        RemoteSessionManager.shared.sendRemoteInput(event)
    }

    public func handleAnnotationAction(stroke: AnnotationStroke?, action: AnnotationAction, point: NormalizedPoint?) {
        guard permissions.isAnnotationAuthorized else { return }
        RemoteSessionManager.shared.sendAnnotation(stroke: stroke, action: action, point: point)
    }

    public func disconnect() {
        frameWatchdogTimer?.invalidate()
        RemoteSessionManager.shared.endSession(reason: "Controller requested disconnect")
        DispatchQueue.main.async { [weak self] in
            self?.onDisconnect?()
        }
    }

    // MARK: - RemoteSessionDelegate

    public func remoteSession(_ session: RemoteSessionManager, didChangeState state: SessionState) {
        DispatchQueue.main.async {
            self.connectionState = state
            if let err = session.lastErrorMessage {
                self.errorMessage = err
            }
            if state == .disconnected {
                self.frameWatchdogTimer?.invalidate()
                self.onDisconnect?()
            }
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didReceiveDecodedImage image: CGImage, timestamp: Double) {
        DispatchQueue.main.async {
            self.currentFrameImage = UIImage(cgImage: image)
            self.isStreamTimedOut = false
            self.lastFrameReceivedTime = Date()
            RemoteMediaSession.shared.recordRenderedFrame()
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didReceiveFrame frameData: Data, timestamp: Double) {
        DispatchQueue.main.async {
            if let uiImage = UIImage(data: frameData) {
                self.currentFrameImage = uiImage
                self.isStreamTimedOut = false
                self.lastFrameReceivedTime = Date()
                RemoteMediaSession.shared.recordRenderedFrame()
            }
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didUpdatePermissions permissions: RemoteSessionPermissions) {
        DispatchQueue.main.async {
            self.permissions = permissions
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didUpdateHealth metrics: MediaHealthMetrics) {
        DispatchQueue.main.async {
            self.healthMetrics = metrics
            self.latencyMs = metrics.rttMs
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didReceiveAnnotation stroke: AnnotationStroke, action: AnnotationAction) {
        DispatchQueue.main.async {
            switch action {
            case .begin, .point:
                break
            case .end:
                self.annotationStrokes.append(stroke)
            case .clear:
                self.annotationStrokes.removeAll()
            case .undo:
                if !self.annotationStrokes.isEmpty {
                    self.annotationStrokes.removeLast()
                }
            }
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didEncounterError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
        }
    }

    public func remoteSessionDidEnd(_ session: RemoteSessionManager, reason: String, endedByHost: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.frameWatchdogTimer?.invalidate()
            self?.onDisconnect?()
        }
    }
}
