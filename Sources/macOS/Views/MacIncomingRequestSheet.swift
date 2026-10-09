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

    private var platformIcon: String {
        switch requester.platform {
        case .macOS: return "macbook"
        case .iOS: return "iphone"
        case .iPadOS: return "ipad"
        case .unknown: return "desktopcomputer"
        }
    }

    public var body: some View {
        VStack(spacing: 18) {
            // Header Hero
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 52, height: 52)

                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 52, height: 52)

                    Image(systemName: platformIcon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Incoming Connection Request")
                            .font(.headline)

                        Text("NEW")
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }

                    Text("\(requester.name) wants to connect to and view this Mac.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            // Presets quick selection
            HStack(spacing: 8) {
                Text("Presets:")
                    .font(.caption.weight(.semibold))
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Granted Session Permissions:")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)

                MacPermissionItem(icon: "display", color: .blue, title: "Screen Viewing", subtitle: "Required to view screen stream", isOn: .constant(true), disabled: true)

                Divider()

                MacPermissionItem(icon: "cursorarrow.rays", color: .green, title: "Mouse Control", subtitle: "Move cursor and click", isOn: $permissions.mouse, disabled: false)
                    .onChange(of: permissions.mouse) { _, newValue in
                        if newValue { permissions.controlScreen = true }
                    }

                Divider()

                MacPermissionItem(icon: "keyboard", color: .indigo, title: "Keyboard Control", subtitle: "Send keystrokes and shortcuts", isOn: $permissions.keyboard, disabled: false)
                    .onChange(of: permissions.keyboard) { _, newValue in
                        if newValue { permissions.controlScreen = true }
                    }

                Divider()

                MacPermissionItem(icon: "pencil.tip.crop.circle.badge.plus", color: .purple, title: "Drawing & Annotations", subtitle: "Draw on screen", isOn: $permissions.annotation, disabled: false)

                Divider()

                MacPermissionItem(icon: "doc.on.clipboard.fill", color: .orange, title: "Clipboard Sync", subtitle: "Bidirectional clipboard sharing", isOn: $permissions.clipboard, disabled: false)

                Divider()

                MacPermissionItem(icon: "folder.badge.gearshape", color: .teal, title: "File Transfer", subtitle: "Send and receive files", isOn: $permissions.fileTransfer, disabled: false)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                Toggle("Remember as default permissions for \(requester.name)", isOn: $rememberAsDefault)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Action Buttons
            HStack {
                Button("Decline Request") {
                    onDecision(false, .viewOnly)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)

                Spacer()

                Button {
                    if rememberAsDefault {
                        TrustModel.shared.updateDefaultPermissions(for: requester.id, permissions: permissions)
                    }
                    onDecision(true, permissions)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Approve Connection")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

private struct MacPermissionItem: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let disabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .disabled(disabled)
                .labelsHidden()
        }
    }
}
