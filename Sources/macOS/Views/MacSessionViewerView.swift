import SwiftUI
import AppKit

public struct MacSessionViewerView: View {
    @ObservedObject var viewModel: MacSessionViewModel
    @State private var annotationTool: AnnotationTool = .freehand
    @State private var annotationColorHex: String = "#FF3B30"
    @State private var isAnnotationModeActive: Bool = false

    public init(viewModel: MacSessionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Controller Toolbar
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.connectionState == .connected ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(viewModel.peerName)
                        .font(.headline)
                    Text("\(Int(viewModel.latencyMs)) ms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(viewModel.isRelayed ? "Relayed" : "Direct P2P")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }

                Spacer()

                // Tool Palette
                HStack(spacing: 8) {
                    // Control mode indicators
                    if viewModel.permissions.mouse {
                        Image(systemName: "cursorarrow.rays")
                            .foregroundColor(.blue)
                            .help("Mouse Control Enabled")
                    }
                    if viewModel.permissions.keyboard {
                        Image(systemName: "keyboard")
                            .foregroundColor(.blue)
                            .help("Keyboard Control Enabled")
                    }

                    Divider().frame(height: 18)

                    // Drawing & Annotation Toggle (if authorized)
                    if viewModel.permissions.annotation {
                        if isAnnotationModeActive {
                            Button(action: { isAnnotationModeActive.toggle() }) {
                                Label("Draw", systemImage: "pencil.tip.crop.circle.badge.plus.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .help("Toggle Drawing & Annotations")
                        } else {
                            Button(action: { isAnnotationModeActive.toggle() }) {
                                Label("Draw", systemImage: "pencil.tip")
                            }
                            .buttonStyle(.bordered)
                            .help("Toggle Drawing & Annotations")
                        }

                        if isAnnotationModeActive {
                            Picker("Tool", selection: $annotationTool) {
                                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                                    Image(systemName: tool.systemImageName).tag(tool)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 130)

                            Button(action: { viewModel.undoLastAnnotation() }) {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            .help("Undo Annotation")

                            Button(action: { viewModel.clearAnnotations() }) {
                                Image(systemName: "trash")
                            }
                            .help("Clear All Annotations")
                        }
                    }

                    Button(action: { viewModel.showDiagnostics = true }) {
                        Image(systemName: "chart.bar.xaxis")
                    }
                    .help("Session Diagnostics")

                    Button(action: { viewModel.showFileTransferModal = true }) {
                        Image(systemName: "arrow.up.doc")
                    }
                    .disabled(!viewModel.permissions.fileTransfer)
                    .help("Send File")

                    // Prominent Disconnect Button
                    Button(action: { viewModel.disconnect() }) {
                        Text("Disconnect")
                            .bold()
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Viewport
            GeometryReader { geometry in
                ZStack {
                    Color.black

                    if let image = viewModel.currentFrameImage {
                        Image(nsImage: image)
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

                        // Non-destructive Annotation Layer
                        MacAnnotationOverlayView(
                            currentTool: $annotationTool,
                            strokes: $viewModel.annotationStrokes,
                            selectedColorHex: $annotationColorHex,
                            isEnabled: isAnnotationModeActive && viewModel.permissions.annotation,
                            onAction: { stroke, action, point in
                                viewModel.handleAnnotationAction(stroke: stroke, action: action, point: point)
                            }
                        )
                    } else if viewModel.isStreamTimedOut {
                        // Diagnostic Fallback for Blank Screen Timeout (Req 56)
                        VStack(spacing: 16) {
                            Image(systemName: "video.slash.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)

                            Text("Remote screen unavailable")
                                .font(.title2)
                                .bold()
                                .foregroundColor(.white)

                            Text("The connection is established, but no video frames are being received from \(viewModel.peerName).")
                                .font(.callout)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            HStack(spacing: 16) {
                                Button("Retry Connection") {
                                    viewModel.retryStream()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Diagnostics") {
                                    viewModel.showDiagnostics = true
                                }
                                .buttonStyle(.bordered)

                                Button("Disconnect") {
                                    viewModel.disconnect()
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(viewModel.connectionState == .reconnecting ? "Reconnecting to \(viewModel.peerName)..." : "Waiting for remote screen stream...")
                                .font(.callout)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showFileTransferModal) {
            MacFileTransferModalView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showDiagnostics) {
            MacDiagnosticsView(
                metrics: viewModel.healthMetrics,
                permissions: viewModel.permissions,
                peerName: viewModel.peerName,
                isHost: false
            )
        }
    }
}

public final class MacSessionViewModel: ObservableObject, RemoteSessionDelegate, @unchecked Sendable {
    @Published public var peerName: String
    @Published public var connectionState: SessionState = .connected
    @Published public var currentFrameImage: NSImage? = nil
    @Published public var latencyMs: Double = 0.0
    @Published public var isRelayed: Bool = false
    @Published public var displays: [DisplayInfo] = []
    @Published public var selectedDisplayIndex: Int = 0
    @Published public var permissions: RemoteSessionPermissions = .standardDefault
    @Published public var annotationStrokes: [AnnotationStroke] = []
    @Published public var healthMetrics: MediaHealthMetrics = MediaHealthMetrics()
    @Published public var isStreamTimedOut: Bool = false
    @Published public var showFileTransferModal: Bool = false
    @Published public var showDiagnostics: Bool = false

    public var onDisconnect: (() -> Void)?

    private var frameWatchdogTimer: Timer?
    private var lastFrameReceivedTime: Date?

    public init(peerName: String) {
        self.peerName = peerName
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
            if self.currentFrameImage == nil, let lastTime = self.lastFrameReceivedTime {
                let elapsed = Date().timeIntervalSince(lastTime)
                if elapsed >= 6.0 {
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

    public func sendRemoteInput(type: RemoteInputEvent.InputType, x: Double, y: Double) {
        guard permissions.isInputAuthorized(for: type) else { return }
        let event = RemoteInputEvent(type: type, x: x, y: y, displayIndex: selectedDisplayIndex)
        RemoteSessionManager.shared.sendRemoteInput(event)
    }

    public func handleAnnotationAction(stroke: AnnotationStroke?, action: AnnotationAction, point: NormalizedPoint?) {
        guard permissions.isAnnotationAuthorized else { return }
        RemoteSessionManager.shared.sendAnnotation(stroke: stroke, action: action, point: point)
    }

    public func clearAnnotations() {
        annotationStrokes.removeAll()
        handleAnnotationAction(stroke: nil, action: .clear, point: nil)
    }

    public func undoLastAnnotation() {
        if !annotationStrokes.isEmpty {
            annotationStrokes.removeLast()
            handleAnnotationAction(stroke: nil, action: .undo, point: nil)
        }
    }

    public func disconnect() {
        frameWatchdogTimer?.invalidate()
        RemoteSessionManager.shared.endSession(reason: "Controller disconnected")
        DispatchQueue.main.async { [weak self] in
            self?.onDisconnect?()
        }
    }

    // MARK: - RemoteSessionDelegate

    public func remoteSession(_ session: RemoteSessionManager, didChangeState state: SessionState) {
        DispatchQueue.main.async {
            self.connectionState = state
            if state == .disconnected || state.isTerminal {
                self.frameWatchdogTimer?.invalidate()
                self.onDisconnect?()
            }
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didReceiveFrame frameData: Data, timestamp: Double) {
        DispatchQueue.main.async {
            if let nsImage = NSImage(data: frameData) {
                self.currentFrameImage = nsImage
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
        print("[MacSessionViewModel] Session error: \(error)")
    }

    public func remoteSessionDidEnd(_ session: RemoteSessionManager, reason: String, endedByHost: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.frameWatchdogTimer?.invalidate()
            self?.onDisconnect?()
        }
    }
}

public struct MacFileTransferModalView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: MacSessionViewModel
    @State private var transferProgress: Float = 0.0
    @State private var statusText: String

    public init(viewModel: MacSessionViewModel) {
        self.viewModel = viewModel
        self._statusText = State(initialValue: "Select a file to transfer to \(viewModel.peerName)")
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("File Transfer")
                .font(.title2)
                .bold()

            Text(statusText)
                .font(.callout)
                .foregroundColor(.secondary)

            if transferProgress > 0 {
                ProgressView(value: transferProgress)
                    .progressViewStyle(.linear)
            }

            HStack {
                Button("Close") { dismiss() }
                Spacer()
                Button("Choose File...") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url {
                        if let (metadata, _) = try? FileTransferManager.shared.prepareFileForSending(fileURL: url) {
                            statusText = "Sending \(metadata.fileName)..."
                            FileTransferManager.shared.onProgressUpdate = { _, progress in
                                DispatchQueue.main.async {
                                    self.transferProgress = progress
                                    if progress >= 1.0 {
                                        self.statusText = "Transfer completed successfully!"
                                    }
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
