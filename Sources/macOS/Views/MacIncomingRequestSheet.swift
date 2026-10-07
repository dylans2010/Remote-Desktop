import SwiftUI

/// Modal sheet presented to host when a remote device requests connection.
public struct MacIncomingRequestSheet: View {
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
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 16) {
                Image(systemName: requester.platform == .macOS ? "macbook" : "iphone")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Incoming Connection Request")
                        .font(.headline)
                    Text("\(requester.name) wants to connect to this Mac.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Presets quick selection
            HStack(spacing: 10) {
                Text("Preset:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("View Only") {
                    permissions = .viewOnly
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Teaching") {
                    permissions = .teaching
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Remote Control") {
                    permissions = .fullControl
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Permissions Checkboxes
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Permissions to Grant:")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.secondary)

                Toggle("View Screen", isOn: $permissions.viewScreen)
                    .disabled(true) // Always required to have a session

                Toggle("Control Mouse", isOn: $permissions.mouse)
                    .onChange(of: permissions.mouse) { _, newValue in
                        if newValue { permissions.controlScreen = true }
                    }

                Toggle("Control Keyboard", isOn: $permissions.keyboard)
                    .onChange(of: permissions.keyboard) { _, newValue in
                        if newValue { permissions.controlScreen = true }
                    }

                Toggle("Drawing & Annotations", isOn: $permissions.annotation)

                Toggle("Clipboard Synchronization", isOn: $permissions.clipboard)

                Toggle("File Transfer", isOn: $permissions.fileTransfer)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Toggle("Remember as default permissions for \(requester.name)", isOn: $rememberAsDefault)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Action Buttons
            HStack {
                Button("Decline") {
                    onDecision(false, .viewOnly)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)

                Spacer()

                Button("Approve Connection") {
                    if rememberAsDefault {
                        TrustModel.shared.updateDefaultPermissions(for: requester.id, permissions: permissions)
                    }
                    onDecision(true, permissions)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
