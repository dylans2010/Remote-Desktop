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
                        .fill(viewModel.connectionState == .connected ? Color.green : (viewModel.isErrorState ? Color.red : Color.orange))
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

                // Tool Palette (Available only when connected)
                if viewModel.connectionState == .connected {
                    HStack(spacing: 8) {
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

                        if viewModel.permissions.annotation {
                            Button(action: { isAnnotationModeActive.toggle() }) {
                                Label("Draw", systemImage: isAnnotationModeActive ? "pencil.tip.crop.circle.badge.plus.fill" : "pencil.tip")
                            }
                            .buttonStyle(.bordered)
                            .tint(isAnnotationModeActive ? .accentColor : .secondary)
                            .help("Toggle Drawing & Annotations")

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

                        Button(action: { viewModel.showFileTransferModal = true }) {
                            Image(systemName: "arrow.up.doc")
                        }
                        .disabled(!viewModel.permissions.fileTransfer)
                        .help("Send File")
                    }
                }

                Button(action: { viewModel.showDiagnostics = true }) {
                    Image(systemName: "chart.bar.xaxis")
                }
                .help("Session Diagnostics")

                // Prominent Disconnect / Leave Button
                Button(action: { viewModel.disconnect() }) {
                    Text(viewModel.isErrorState ? "Close" : "Disconnect")
                        .bold()
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Viewport
            GeometryReader { geometry in
                ZStack {
                    Color.black

                    if let image = viewModel.currentFrameImage, viewModel.connectionState == .connected {
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
                    } else if viewModel.isErrorState {
                        // Actionable Error View (Section 5, 26) - Stays visible instead of silently popping!
                        VStack(spacing: 20) {
                            Image(systemName: errorSystemIcon(for: viewModel.connectionState))
                                .font(.system(size: 56))
                                .foregroundColor(.red)

                            VStack(spacing: 8) {
                                Text(viewModel.connectionState.statusDescription)
                                    .font(.title2)
                                    .bold()
                                    .foregroundColor(.white)

                                Text(viewModel.errorMessage ?? defaultErrorDetail(for: viewModel.connectionState))
                                    .font(.callout)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 480)
                            }

                            // Diagnostic summary
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Diagnostic Summary")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.secondary)
                                HStack(spacing: 20) {
                                    Text("Capture: \(viewModel.connectionState == .captureUnavailable ? "Denied" : "OK")")
                                    Text("Transport: \(viewModel.connectionState == .transportFailed ? "Failed" : "OK")")
                                    Text("Frames Received: \(viewModel.healthMetrics.framesReceived)")
                                }
                                .font(.caption2)
                                .foregroundColor(.white)
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(8)

                            HStack(spacing: 16) {
                                Button("Retry Connection") {
                                    viewModel.retryConnection()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Diagnostics") {
                                    viewModel.showDiagnostics = true
                                }
                                .buttonStyle(.bordered)

                                Button("Return to Devices") {
                                    viewModel.disconnect()
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(32)
                    } else if viewModel.isStreamTimedOut {
                        // Blank Screen Watchdog View (Section 15)
                        VStack(spacing: 16) {
                            Image(systemName: "video.slash.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)

                            Text("Screen stream failed")
                                .font(.title2)
                                .bold()
                                .foregroundColor(.white)

                            Text("The connection is authenticated, but no video frames are arriving from \(viewModel.peerName).")
                                .font(.callout)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 460)

                            HStack(spacing: 16) {
                                Button("Retry Stream") {
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
                        // Connection Progress State (Section 5, 26)
                        VStack(spacing: 16) {
                            ProgressView()
                                .controlSize(.large)
                            Text(viewModel.connectionState.statusDescription)
                                .font(.title3)
                                .bold()
                                .foregroundColor(.white)
                            Text("Connecting to \(viewModel.peerName)...")
                                .font(.callout)
                                .foregroundColor(.gray)

                            Button("Cancel") {
                                viewModel.disconnect()
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 12)
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

    private func errorSystemIcon(for state: SessionState) -> String {
        switch state {
        case .permissionDenied: return "hand.raised.fill"
        case .captureUnavailable: return "video.slash.fill"
        case .authenticationFailed: return "lock.slash.fill"
        case .transportFailed: return "wifi.slash"
        case .connectionTimeout: return "clock.badge.exclamationmark.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private func defaultErrorDetail(for state: SessionState) -> String {
        switch state {
        case .permissionDenied:
            return "The host declined your remote desktop request."
        case .captureUnavailable:
            return "Screen Recording permission is required on the host Mac in System Settings -> Privacy & Security -> Screen Recording."
        case .authenticationFailed:
            return "Cryptographic device identity could not be verified with the host."
        case .transportFailed:
            return "Unable to maintain network transport with host. Please check network connectivity."
        case .connectionTimeout:
            return "Connection attempt timed out. The host did not respond in time."
        default:
            return "The session could not be established."
        }
    }
}

public final class MacSessionViewModel: ObservableObject, RemoteSessionDelegate, @unchecked Sendable {
    @Published public var peerName: String
    @Published public var targetDevice: Device?
    @Published public var connectionState: SessionState = .connecting
    @Published public var currentFrameImage: NSImage? = nil
    @Published public var latencyMs: Double = 0.0
    @Published public var isRelayed: Bool = false
    @Published public var displays: [DisplayInfo] = []
    @Published public var selectedDisplayIndex: Int = 0
    @Published public var permissions: RemoteSessionPermissions = .standardDefault
    @Published public var annotationStrokes: [AnnotationStroke] = []
    @Published public var healthMetrics: MediaHealthMetrics = MediaHealthMetrics()
    @Published public var isStreamTimedOut: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var showFileTransferModal: Bool = false
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

    public func sendFile(url: URL) {
        Task {
            do {
                let (metadata, chunks) = try FileTransferManager.shared.prepareFileForSending(fileURL: url)
                let offerPayload = try JSONEncoder().encode(metadata)
                let offerMsg = ProtocolMessage(
                    type: .fileOffer,
                    senderID: DeviceIdentity.current.deviceID,
                    targetID: peerName,
                    payload: offerPayload
                )
                try await RemoteSessionManager.shared.activeTransport?.sendMessage(offerMsg)
                for (idx, chunkData) in chunks.enumerated() {
                    let chunkPayload = FileChunkPayload(
                        transferID: metadata.transferID,
                        chunkIndex: idx,
                        data: chunkData
                    )
                    let encodedChunk = try JSONEncoder().encode(chunkPayload)
                    let chunkMsg = ProtocolMessage(
                        type: .fileChunk,
                        senderID: DeviceIdentity.current.deviceID,
                        targetID: self.peerName,
                        payload: encodedChunk
                    )
                    try await RemoteSessionManager.shared.activeTransport?.sendMessage(chunkMsg)
                }
            } catch {
                print("[FileTransfer] Failed to send file: \(error.localizedDescription)")
            }
        }
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
            let size = NSSize(width: image.width, height: image.height)
            self.currentFrameImage = NSImage(cgImage: image, size: size)
            self.isStreamTimedOut = false
            self.lastFrameReceivedTime = Date()
            RemoteMediaSession.shared.recordRenderedFrame()
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
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
        }
    }

    public func remoteSessionDidEnd(_ session: RemoteSessionManager, reason: String, endedByHost: Bool) {
        DispatchQueue.main.async {
            self.frameWatchdogTimer?.invalidate()
            self.onDisconnect?()
        }
    }
}

// MARK: - File Transfer Modal View

struct MacFileTransferModalView: View {
    @ObservedObject var viewModel: MacSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFileURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Text("File Transfer")
                .font(.headline)

            if let url = selectedFileURL {
                VStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.blue)
                    Text(url.lastPathComponent)
                        .font(.subheadline)
                        .bold()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))

                Button("Send File to Remote") {
                    viewModel.sendFile(url: url)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Select a file to send to \(viewModel.peerName):")
                    .foregroundColor(.secondary)

                Button("Choose File…") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url {
                        selectedFileURL = url
                    }
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 360, height: 260)
    }
}
