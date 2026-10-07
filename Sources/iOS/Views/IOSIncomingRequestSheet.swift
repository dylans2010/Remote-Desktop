import SwiftUI

/// Modal sheet presented on iOS when a remote device requests connection.
public struct IOSIncomingRequestSheet: View {
    public let requester: Device
    @State private var permissions: RemoteSessionPermissions
    @State private var rememberAsDefault: Bool = true
    public var onDecision: (Bool, RemoteSessionPermissions) -> Void

    public init(requester: Device, initialPermissions: RemoteSessionPermissions = .standardDefault, onDecision: @escaping (Bool, RemoteSessionPermissions) -> Void) {
        self.requester = requester
        self._permissions = State(initialValue: initialPermissions)
        self.onDecision = onDecision
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Device")) {
                    HStack(spacing: 12) {
                        Image(systemName: requester.platform == .macOS ? "macbook" : "iphone")
                            .font(.title)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(requester.name)
                                .font(.headline)
                            Text(requester.platform.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Granted Permissions")) {
                    Toggle("View Screen", isOn: $permissions.viewScreen)
                        .disabled(true)

                    Toggle("Annotations & Drawing", isOn: $permissions.annotation)
                    Toggle("Clipboard Synchronization", isOn: $permissions.clipboard)
                }

                Section {
                    Toggle("Remember for \(requester.name)", isOn: $rememberAsDefault)
                }

                Section {
                    Button(role: .destructive, action: {
                        onDecision(false, .viewOnly)
                    }) {
                        Text("Decline Connection")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Button(action: {
                        if rememberAsDefault {
                            TrustModel.shared.updateDefaultPermissions(for: requester.id, permissions: permissions)
                        }
                        onDecision(true, permissions)
                    }) {
                        Text("Approve Connection")
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Connection Request")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
