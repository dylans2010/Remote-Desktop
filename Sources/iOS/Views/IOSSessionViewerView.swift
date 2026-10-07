import SwiftUI
import UIKit

public struct IOSSessionViewerView: View {
    @ObservedObject var viewModel: IOSSessionViewModel

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
                        Text("\(Int(viewModel.latencyMs)) ms")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text(viewModel.isRelayed ? "Relay" : "Direct P2P")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(viewModel.isRelayed ? Color.orange : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(3)
                    }
                }

                Spacer()

                Button(action: { viewModel.disconnect() }) {
                    Text("Disconnect")
                        .font(.subheadline)
                        .bold()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black)

            // Remote Screen Viewport
            GeometryReader { geometry in
                ZStack {
                    Color.black

                    if let image = viewModel.currentFrameImage {
                        Image(uiImage: image)
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
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Connecting to \(viewModel.peerName)...")
                                .font(.callout)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .edgesIgnoringSafeArea(.bottom)
    }
}

public final class IOSSessionViewModel: ObservableObject, RemoteSessionDelegate, @unchecked Sendable {
    @Published public var peerName: String
    @Published public var connectionState: TransportConnectionState = .connected
    @Published public var currentFrameImage: UIImage? = nil
    @Published public var latencyMs: Double = 31.0
    @Published public var isRelayed: Bool = false

    public init(peerName: String) {
        self.peerName = peerName
        RemoteSessionManager.shared.delegate = self
    }

    public func sendRemoteInput(type: RemoteInputEvent.InputType, x: Double, y: Double) {
        let event = RemoteInputEvent(type: type, x: x, y: y)
        RemoteSessionManager.shared.sendRemoteInput(event)
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
            if let uiImage = UIImage(data: frameData) {
                self.currentFrameImage = uiImage
            }
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didUpdateMetrics latencyMs: Double, bitrateMbps: Double) {
        DispatchQueue.main.async {
            self.latencyMs = latencyMs
        }
    }

    public func remoteSession(_ session: RemoteSessionManager, didEncounterError error: Error) {
        print("[IOSSessionViewModel] Session error: \(error)")
    }
}
