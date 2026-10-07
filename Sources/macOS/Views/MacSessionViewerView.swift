import SwiftUI
import AppKit

public struct MacSessionViewerView: View {
    @ObservedObject var viewModel: MacSessionViewModel

    public init(viewModel: MacSessionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.connectionState == .connected ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(viewModel.peerName)
                        .font(.headline)
                    Text("\(Int(viewModel.latencyMs)) ms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if viewModel.isRelayed {
                        Text("Relayed")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    } else {
                        Text("Direct P2P")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    if !viewModel.displays.isEmpty {
                        Picker("Display", selection: $viewModel.selectedDisplayIndex) {
                            ForEach(0..<viewModel.displays.count, id: \.self) { idx in
                                Text(viewModel.displays[idx].name).tag(idx)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 160)
                    }

                    Button(action: { viewModel.toggleClipboardSync() }) {
                        Label("Clipboard", systemImage: viewModel.isClipboardEnabled ? "doc.on.clipboard.fill" : "doc.on.clipboard")
                    }
                    .help("Toggle Clipboard Sync")

                    Button(action: { viewModel.showFileTransferModal = true }) {
                        Label("File Transfer", systemImage: "arrow.up.doc")
                    }
                    .help("Send File")

                    Button(action: { viewModel.disconnect() }) {
                        Text("Disconnect")
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
                                        let normX = value.location.x / geometry.size.width
                                        let normY = value.location.y / geometry.size.height
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
            MacFileTransferModalView(viewModel: viewModel)
        }
    }
}

public final class MacSessionViewModel: ObservableObject, RemoteSessionDelegate, @unchecked Sendable {
    @Published public var peerName: String
    @Published public var connectionState: TransportConnectionState = .connected
    @Published public var currentFrameImage: NSImage? = nil
    @Published public var latencyMs: Double = 24.0
    @Published public var isRelayed: Bool = false
    @Published public var displays: [DisplayInfo] = []
    @Published public var selectedDisplayIndex: Int = 0
    @Published public var isClipboardEnabled: Bool = true
    @Published public var showFileTransferModal: Bool = false

    public var onDisconnect: (() -> Void)?

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
        DispatchQueue.main.async { [weak self] in
            self?.onDisconnect?()
        }
    }

    // MARK: - RemoteSessionDelegate

    public func remoteSession(_ session: RemoteSessionManager, didChangeState state: TransportConnectionState) {
        DispatchQueue.main.async {
            self.connectionState = state
            if state == .disconnected {
                self.onDisconnect?()
            }
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
        print("[MacSessionViewModel] Session error: \(error)")
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
