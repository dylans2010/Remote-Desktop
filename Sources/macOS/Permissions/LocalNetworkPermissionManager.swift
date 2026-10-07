import Foundation
import Network

/// Manages macOS Local Network permissions and service advertising state.
public final class LocalNetworkPermissionManager: @unchecked Sendable {
    public static let shared = LocalNetworkPermissionManager()

    private init() {}

    /// Trigger local network authorization by initializing a local test listener.
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
