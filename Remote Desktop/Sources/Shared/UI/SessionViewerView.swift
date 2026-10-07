import SwiftUI

public struct SessionViewerView: View {
    @ObservedObject var viewModel: SessionViewModel

    public init(viewModel: SessionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Native Lightweight Toolbar
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.connectionState == .connected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(viewModel.peerName)
                        .font(.headline)
                }

                Spacer()

                // Diagnostics metrics
                HStack(spacing: 12) {
                    Label("\(Int(viewModel.latencyMs)) ms", systemImage: "network")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label(viewModel.isRelayed ? "Relayed" : "Direct P2P", systemImage: viewModel.isRelayed ? "arrow.triangle.2.circlepath" : "bolt.fill")
                        .font(.caption)
                        .foregroundColor(viewModel.isRelayed ? .orange : .green)
                }

                Divider().frame(height: 16)

                // Multi-display selector
                if viewModel.displays.count > 1 {
                    Picker("Display", selection: $viewModel.selectedDisplayIndex) {
                        ForEach(0..<viewModel.displays.count, id: \.self) { idx in
                            Text("Display \(idx + 1)").tag(idx)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }

                Button(action: { viewModel.toggleClipboardSync() }) {
                    Image(systemName: viewModel.isClipboardEnabled ? "doc.on.clipboard.fill" : "doc.on.clipboard")
                }
                .help("Clipboard Synchronization")

                Button(action: { viewModel.showFileTransferModal = true }) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Transfer Files")

                Button(role: .destructive, action: { viewModel.disconnect() }) {
                    Text("Disconnect")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Remote Screen Render Viewport
            GeometryReader { geometry in
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)

                    if let image = viewModel.currentFrameImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let normX = Double(value.location.x / geometry.size.width)
                                        let normY = Double(value.location.y / geometry.size.height)
                                        // Transmit remote input over network to remote host
                                        viewModel.sendRemoteInput(type: .mouseMove, x: normX, y: normY)
                                    }
                            )
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
            FileTransferModalView(viewModel: viewModel)
        }
    }
}

public final class SessionViewModel: ObservableObject, RemoteSessionDelegate, @unchecked Sendable {
    @Published public var peerName: String
    @Published public var connectionState: TransportConnectionState = .connected
    @Published public var currentFrameImage: NSImage? = nil
    @Published public var latencyMs: Double = 24.0
    @Published public var isRelayed: Bool = false
    @Published public var displays: [DisplayInfo] = []
    @Published public var selectedDisplayIndex: Int = 0
    @Published public var isClipboardEnabled: Bool = true
    @Published public var showFileTransferModal: Bool = false

    public init(peerName: String) {
        self.peerName = peerName
        RemoteSessionManager.shared.delegate = self
    }

    public func sendRemoteInput(type: RemoteInputEvent.InputType, x: Double, y: Double) {
        let event = RemoteInputEvent(type: type, x: x, y: y, displayIndex: selectedDisplayIndex)
        RemoteSessionManager.shared.sendRemoteInput(event)
    }

    public func toggleClipboardSync() {
        isClipboardEnabled.toggle()
        ClipboardSyncManager.shared.currentPolicy = isClipboardEnabled ? .automatic : .disabled
    }

    public func disconnect() {
        RemoteSessionManager.shared.endSession()
    }

    // MARK: - RemoteSessionDelegate

    public func remoteSession(_ session: RemoteSessionManager, didChangeState state: TransportConnectionState) {
        DispatchQueue.main.async {
            self.connectionState = state
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didReceiveFrame frameData: Data, timestamp: Double) {
        DispatchQueue.main.async {
            if let nsImage = NSImage(data: frameData) {
                self.currentFrameImage = nsImage
            }
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didUpdateMetrics latencyMs: Double, bitrateMbps: Double) {
        DispatchQueue.main.async {
            self.latencyMs = latencyMs
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didEncounterError error: Error) {
        print("[SessionViewModel] Session error: \(error)")
    }
}

public struct FileTransferModalView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SessionViewModel
    @State private var transferProgress: Float = 0.0
    @State private var statusText: String = "Select a file to transfer to \(viewModel.peerName)"

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
