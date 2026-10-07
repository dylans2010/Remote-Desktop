import Foundation
import Network

/// Manages iOS Local Network permission authorization.
public final class IOSLocalNetworkPermissionManager: @unchecked Sendable {
    public static let shared = IOSLocalNetworkPermissionManager()

    private init() {}

    /// Trigger local network authorization dialog on iOS.
    public func triggerPermissionPrompt() {
        let params = NWParameters.tcp
        if let listener = try? NWListener(using: params) {
            listener.stateUpdateHandler = { state in
                if case .failed(_) = state {
                    listener.cancel()
                }
            }
            listener.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                listener.cancel()
            }
        }
    }
}
