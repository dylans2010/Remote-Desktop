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

    private var platformIcon: String {
        switch requester.platform {
        case .macOS: return "macbook"
        case .iOS: return "iphone"
        case .iPadOS: return "ipad"
        case .unknown: return "desktopcomputer"
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Hero Requester Card
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 80, height: 80)

                            Circle()
                                .stroke(Color.blue.opacity(0.35), lineWidth: 2)
                                .frame(width: 80, height: 80)

                            Image(systemName: platformIcon)
                                .font(.system(size: 38, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .padding(.top, 8)

                        VStack(spacing: 4) {
                            Text(requester.name)
                                .font(.title2.weight(.bold))

                            HStack(spacing: 6) {
                                Text(requester.platform.rawValue)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.secondary)

                                if let ip = requester.ipAddress, !ip.isEmpty {
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(ip)
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Text("wants to connect and view your screen")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal)

                    // Permissions Configuration Card
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Requested Permissions", systemImage: "hand.raised.fill")
                            .font(.headline)
                            .foregroundColor(.primary)

                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "display")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Screen Viewing")
                                        .font(.subheadline.weight(.medium))
                                    Text("Required to view screen stream")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: $permissions.viewScreen)
                                    .disabled(true)
                                    .labelsHidden()
                            }

                            Divider()

                            HStack(spacing: 12) {
                                Image(systemName: "pencil.tip.crop.circle.badge.plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.purple)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Live Annotations")
                                        .font(.subheadline.weight(.medium))
                                    Text("Allow peer to draw on your display")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: $permissions.annotation)
                                    .labelsHidden()
                            }

                            Divider()

                            HStack(spacing: 12) {
                                Image(systemName: "doc.on.clipboard.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Clipboard Sync")
                                        .font(.subheadline.weight(.medium))
                                    Text("Share copied text between devices")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: $permissions.clipboard)
                                    .labelsHidden()
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal)

                    // Remember Trust Toggle Card
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trust \(requester.name)")
                                .font(.subheadline.weight(.semibold))
                            Text("Save permissions for automatic future connections")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $rememberAsDefault)
                            .labelsHidden()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal)

                    Spacer(minLength: 16)

                    // Decision Buttons
                    VStack(spacing: 12) {
                        Button {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            if rememberAsDefault {
                                TrustModel.shared.updateDefaultPermissions(for: requester.id, permissions: permissions)
                            }
                            onDecision(true, permissions)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Approve Connection")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                LinearGradient(
                                    colors: [Color.green, Color(red: 0.15, green: 0.75, blue: 0.35)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.green.opacity(0.3), radius: 8, x: 0, y: 4)
                        }

                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onDecision(false, .viewOnly)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Decline Connection")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.red.opacity(0.12))
                            .foregroundColor(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .padding(.vertical, 10)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Connection Request")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
