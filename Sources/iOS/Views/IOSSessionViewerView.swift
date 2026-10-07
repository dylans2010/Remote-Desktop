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

    public var body: some View {
        VStack(spacing: 0) {
            // Status bar header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.peerName)
                        .font(.headline)
                        .foregroundColor(.white)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.connectionState == .connected ? Color.green : (viewModel.isErrorState ? Color.red : Color.orange))
                            .frame(width: 8, height: 8)
                        Text("\(Int(viewModel.latencyMs)) ms")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text(viewModel.isRelayed ? "Relay" : "Direct P2P")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(3)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    if viewModel.connectionState == .connected && viewModel.permissions.annotation {
                        Button(action: { isAnnotationModeActive.toggle() }) {
                            Image(systemName: isAnnotationModeActive ? "pencil.tip.crop.circle.badge.plus.fill" : "pencil.tip")
                                .font(.title3)
                                .foregroundColor(isAnnotationModeActive ? .yellow : .white)
                        }
                    }

                    Button(action: { viewModel.showDiagnostics = true }) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.title3)
                            .foregroundColor(.white)
                    }

                    Button(action: { viewModel.disconnect() }) {
                        Text(viewModel.isErrorState ? "Close" : "Disconnect")
                            .font(.subheadline)
                            .bold()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black)

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
                        // Actionable Error View (Section 5, 26) - Never immediately pops!
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.red)

                            VStack(spacing: 8) {
                                Text(viewModel.connectionState.statusDescription)
                                    .font(.title2)
                                    .bold()
                                    .foregroundColor(.white)

                                Text(viewModel.errorMessage ?? "The connection could not be established.")
                                    .font(.callout)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }

                            HStack(spacing: 16) {
                                Button("Retry Connection") {
                                    viewModel.retryConnection()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)

                                Button("Return to Devices") {
                                    viewModel.disconnect()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                        .padding(24)
                    } else if viewModel.isStreamTimedOut {
                        // Blank Screen Detection (Section 15)
                        VStack(spacing: 16) {
                            Image(systemName: "video.slash.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)

                            Text("Screen stream failed")
                                .font(.title3)
                                .bold()
                                .foregroundColor(.white)

                            Text("Connected to \(viewModel.peerName), but no video frames are arriving.")
                                .font(.caption)
                                .foregroundColor(.gray)

                            HStack(spacing: 12) {
                                Button("Retry Stream") {
                                    viewModel.retryStream()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Disconnect") {
                                    viewModel.disconnect()
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            }
                        }
                    } else {
                        // Connecting Progress View (Section 5, 26)
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.4)
                            Text(viewModel.connectionState.statusDescription)
                                .font(.title3)
                                .foregroundColor(.white)
                            Text("Connecting to \(viewModel.peerName)...")
                                .font(.caption)
                                .foregroundColor(.gray)

                            Button("Cancel") {
                                viewModel.disconnect()
                            }
                            .padding(.top, 8)
                            .foregroundColor(.red)
                        }
                    }
                }
            }

            // Annotation Palette Bar
            if isAnnotationModeActive && viewModel.permissions.annotation {
                HStack(spacing: 20) {
                    ForEach(AnnotationTool.allCases, id: \.self) { tool in
                        Button(action: { annotationTool = tool }) {
                            Image(systemName: tool.systemImageName)
                                .foregroundColor(annotationTool == tool ? .yellow : .white)
                        }
                    }

                    Spacer()

                    Button(action: {
                        if !viewModel.annotationStrokes.isEmpty {
                            viewModel.annotationStrokes.removeLast()
                            viewModel.handleAnnotationAction(stroke: nil, action: .undo, point: nil)
                        }
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundColor(.white)
                    }

                    Button(action: {
                        viewModel.annotationStrokes.removeAll()
                        viewModel.handleAnnotationAction(stroke: nil, action: .clear, point: nil)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.85))
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
