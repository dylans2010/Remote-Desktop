import Foundation

/// Delegate protocol receiving signaling network lifecycle events.
public protocol SignalingClientDelegate: AnyObject {
    func signalingClient(_ client: SignalingClient, didConnect sessionID: String)
    func signalingClient(_ client: SignalingClient, didReceiveOffer offer: ProtocolMessage)
    func signalingClient(_ client: SignalingClient, didReceiveAnswer answer: ProtocolMessage)
    func signalingClient(_ client: SignalingClient, didReceiveICECandidate candidate: ProtocolMessage)
    func signalingClient(_ client: SignalingClient, didDisconnectWithError error: Error?)
}

/// Minimal WebSocket/HTTP stateless signaling protocol client for internet peer rendezvous and SDP/ICE candidate exchange.
public final class SignalingClient: NSObject, @unchecked Sendable {
    public weak var delegate: SignalingClientDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession
    private let serverURL: URL
    private let lock = NSLock()

    public init(serverURL: URL) {
        self.serverURL = serverURL
        self.urlSession = URLSession(configuration: .default)
        super.init()
    }

    /// Connect to remote signaling service endpoint.
    public func connect(deviceID: String) {
        lock.lock()
        defer { lock.unlock() }

        var request = URLRequest(url: serverURL)
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")

        let task = urlSession.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        receiveMessages()
        delegate?.signalingClient(self, didConnect: deviceID)
    }

    /// Send offer, answer, or ICE candidate metadata through signaling channel.
    public func sendSignalingMessage(_ message: ProtocolMessage) {
        guard let data = try? ProtocolEngine.encode(message) else { return }
        let wsMessage = URLSessionWebSocketTask.Message.data(data)

        lock.lock()
        let task = webSocketTask
        lock.unlock()

        task?.send(wsMessage) { error in
            if let error = error {
                print("[SignalingClient] Failed to send message: \(error)")
            }
        }
    }

    /// Disconnect signaling session once P2P or TURN relay channel is established.
    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    private func receiveMessages() {
        lock.lock()
        let task = webSocketTask
        lock.unlock()

        task?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let wsMessage):
                var messageData: Data?
                switch wsMessage {
                case .data(let data):
                    messageData = data
                case .string(let text):
                    messageData = text.data(using: .utf8)
                @unknown default:
                    break
                }

                if let data = messageData, let msg = try? ProtocolEngine.decode(data) {
                    switch msg.type {
                    case .sessionOffer:
                        self.delegate?.signalingClient(self, didReceiveOffer: msg)
                    case .sessionAnswer:
                        self.delegate?.signalingClient(self, didReceiveAnswer: msg)
                    case .iceCandidate:
                        self.delegate?.signalingClient(self, didReceiveICECandidate: msg)
                    default:
                        break
                    }
                }

                // Recursively listen for next incoming WebSocket message
                self.receiveMessages()

            case .failure(let error):
                self.delegate?.signalingClient(self, didDisconnectWithError: error)
            }
        }
    }
}
