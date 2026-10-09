import SwiftUI

public struct IOSDeviceListView: View {
    @Binding var selectedDevice: Device?
    var devices: [Device]
    var onConnect: (Device) -> Void
    var onPairClicked: () -> Void

    @State private var filterSelection: Int = 0 // 0: All, 1: Macs, 2: iOS
    @State private var pulseAnimation: Bool = false

    public init(
        selectedDevice: Binding<Device?>,
        devices: [Device],
        onConnect: @escaping (Device) -> Void,
        onPairClicked: @escaping () -> Void
    ) {
        self._selectedDevice = selectedDevice
        self.devices = devices
        self.onConnect = onConnect
        self.onPairClicked = onPairClicked
    }

    private var filteredDevices: [Device] {
        switch filterSelection {
        case 1:
            return devices.filter { $0.platform == .macOS }
        case 2:
            return devices.filter { $0.platform == .iOS || $0.platform == .iPadOS }
        default:
            return devices
        }
    }

    public var body: some View {
        List {
            // Local Discovery Status Banner
            Section {
                LocalDiscoveryBanner(pulseAnimation: $pulseAnimation)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // Screen Broadcast Section (ReplayKit Hero Card)
            Section {
                ScreenBroadcastHeroCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Label("Live Screen Broadcast", systemImage: "airplayvideo.badge.waveform")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(nil)
            }

            // Discovered & Paired Devices Section
            Section {
                if !devices.isEmpty {
                    Picker("Device Filter", selection: $filterSelection) {
                        Text("All (\(devices.count))").tag(0)
                        Text("Macs (\(devices.filter { $0.platform == .macOS }.count))").tag(1)
                        Text("iOS (\(devices.filter { $0.platform != .macOS }.count))").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
                }

                if filteredDevices.isEmpty && !devices.isEmpty {
                    Text("No devices match this filter.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                } else if devices.isEmpty {
                    EmptyDevicesCard(onPairClicked: onPairClicked)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredDevices) { device in
                        NavigationLink(value: device) {
                            DeviceRowCard(device: device) {
                                onConnect(device)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
            } header: {
                HStack {
                    Label("Discovered Devices", systemImage: "network")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                    Spacer()
                    if !devices.isEmpty {
                        Text("\(devices.filter { $0.onlineState == .online }.count) online")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            pulseAnimation = true
        }
    }
}

// MARK: - Local Discovery Banner

private struct LocalDiscoveryBanner: View {
    @Binding var pulseAnimation: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 48, height: 48)

                Circle()
                    .stroke(Color.blue.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 48, height: 48)
                    .scaleEffect(pulseAnimation ? 1.15 : 0.95)
                    .opacity(pulseAnimation ? 0.4 : 0.8)
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Local Discovery Active")
                        .font(.subheadline.weight(.semibold))
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                }

                Text("Broadcasting zero-config Bonjour on local Wi-Fi")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "wifi")
                .font(.footnote.weight(.medium))
                .foregroundColor(.blue)
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

// MARK: - ReplayKit Screen Broadcast Hero Card

private struct ScreenBroadcastHeroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    LinearGradient(
                        colors: [Color.indigo, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Image(systemName: "airplayvideo")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Broadcast Screen to Mac")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("ReplayKit")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .clipShape(Capsule())
                    }

                    Text("Stream this iPhone screen live to your connected Mac over low-latency P2P.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("Tap picker to launch broadcast")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                BroadcastPickerView(preferredExtensionBundleID: "com.dylans2010.RemoteDesktop.BroadcastExtension")
                    .frame(width: 44, height: 44)
                    .background(Color.purple.opacity(0.12))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.purple.opacity(0.3), lineWidth: 1))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.10),
                            Color.indigo.opacity(0.05),
                            Color(UIColor.secondarySystemGroupedBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.purple.opacity(0.25), lineWidth: 1.2)
                )
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Device Row Card

private struct DeviceRowCard: View {
    let device: Device
    let onConnect: () -> Void

    private var platformGradient: LinearGradient {
        if device.platform == .macOS {
            return LinearGradient(
                colors: [Color.blue, Color.indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color.teal, Color.blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var platformIcon: String {
        switch device.platform {
        case .macOS:
            return "macbook"
        case .iOS:
            return "iphone"
        case .iPadOS:
            return "ipad"
        case .unknown:
            return "desktopcomputer"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Platform Icon Badge
            ZStack {
                platformGradient
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: device.platform == .macOS ? Color.blue.opacity(0.25) : Color.teal.opacity(0.25), radius: 6, x: 0, y: 3)

                Image(systemName: platformIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }

            // Info Column
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)

                    if device.trustStatus == .trusted {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(device.onlineState == .online ? Color.green : Color.gray)
                            .frame(width: 7, height: 7)
                        Text(device.onlineState.rawValue.capitalized)
                            .font(.caption)
                            .foregroundColor(device.onlineState == .online ? .primary : .secondary)
                    }

                    if let ip = device.ipAddress, !ip.isEmpty {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(ip)
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if device.onlineState == .online {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onConnect()
                } label: {
                    HStack(spacing: 4) {
                        Text("Connect")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color(red: 0.2, green: 0.4, blue: 0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty Devices Card

private struct EmptyDevicesCard: View {
    let onPairClicked: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 72, height: 72)

                Image(systemName: "desktopcomputer.and.arrow.down")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("No Nearby Devices Found")
                    .font(.headline)

                Text("Ensure Remote Desktop is open on your Mac and connected to the same Wi-Fi network.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onPairClicked()
            } label: {
                Label("Pair New Device with Code", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Device Detail View

public struct IOSDeviceDetailView: View {
    let device: Device
    var onConnect: () -> Void
    @State private var defaultPermissions: RemoteSessionPermissions
    @State private var isTrusted: Bool
    @State private var showingRevokeConfirmation: Bool = false

    public init(device: Device, onConnect: @escaping () -> Void) {
        self.device = device
        self.onConnect = onConnect
        self._defaultPermissions = State(initialValue: TrustModel.shared.defaultPermissions(for: device.id))
        self._isTrusted = State(initialValue: TrustModel.shared.isTrusted(deviceID: device.id))
    }

    private var platformIcon: String {
        switch device.platform {
        case .macOS: return "macbook"
        case .iOS: return "iphone"
        case .iPadOS: return "ipad"
        case .unknown: return "desktopcomputer"
        }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero Card
                VStack(spacing: 12) {
                    ZStack {
                        LinearGradient(
                            colors: device.platform == .macOS ? [Color.blue, Color.indigo] : [Color.teal, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)

                        Image(systemName: platformIcon)
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 10)

                    VStack(spacing: 4) {
                        Text(device.name)
                            .font(.title2.weight(.bold))

                        HStack(spacing: 6) {
                            Circle()
                                .fill(device.onlineState == .online ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(device.onlineState.rawValue.capitalized)
                                .font(.caption.weight(.medium))
                                .foregroundColor(device.onlineState == .online ? .green : .secondary)

                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text(device.platform.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Trust Pill
                    HStack(spacing: 6) {
                        Image(systemName: isTrusted ? "checkmark.shield.fill" : "shield.slash.fill")
                            .foregroundColor(isTrusted ? .green : .secondary)
                        Text(isTrusted ? "Trusted Device (Fast Connect)" : "Untrusted Device (Approval Required)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(isTrusted ? .green : .secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isTrusted ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                )
                .padding(.horizontal)

                // Permissions Section Card
                VStack(alignment: .leading, spacing: 14) {
                    Label("Default Session Permissions", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(spacing: 12) {
                        PermissionRow(
                            icon: "display",
                            color: .blue,
                            title: "Screen Viewing",
                            subtitle: "View high-definition live screen stream",
                            isOn: .constant(true),
                            disabled: true
                        )

                        Divider()

                        PermissionRow(
                            icon: "pencil.tip.crop.circle.badge.plus",
                            color: .purple,
                            title: "Live Annotations",
                            subtitle: "Draw and highlight directly on remote screen",
                            isOn: $defaultPermissions.annotation,
                            disabled: false
                        )
                        .onChange(of: defaultPermissions.annotation) { _, _ in
                            saveDefaults()
                        }

                        Divider()

                        PermissionRow(
                            icon: "doc.on.clipboard.fill",
                            color: .orange,
                            title: "Clipboard Synchronization",
                            subtitle: "Bidirectional copy & paste sync",
                            isOn: $defaultPermissions.clipboard,
                            disabled: false
                        )
                        .onChange(of: defaultPermissions.clipboard) { _, _ in
                            saveDefaults()
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                )
                .padding(.horizontal)

                // Connect Button
                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    onConnect()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                        Text("Connect to \(device.name)")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        device.onlineState == .online ?
                        LinearGradient(colors: [Color.blue, Color(red: 0.15, green: 0.35, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(colors: [Color.gray, Color.gray.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: device.onlineState == .online ? Color.blue.opacity(0.35) : Color.clear, radius: 8, x: 0, y: 4)
                }
                .disabled(device.onlineState != .online)
                .padding(.horizontal)

                // Trust Management / Revocation
                if isTrusted {
                    Button(role: .destructive) {
                        showingRevokeConfirmation = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.shield.fill")
                            Text("Revoke Trust")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal)
                    .confirmationDialog("Revoke Trust?", isPresented: $showingRevokeConfirmation, titleVisibility: .visible) {
                        Button("Revoke Trust", role: .destructive) {
                            TrustModel.shared.revokeDevice(deviceID: device.id)
                            isTrusted = false
                            ToastManager.shared.showWarning(
                                title: "Trust Revoked",
                                message: "\(device.name) will require explicit approval for future connections."
                            )
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Future incoming or outgoing sessions with \(device.name) will require manual authorization.")
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveDefaults() {
        TrustModel.shared.updateDefaultPermissions(for: device.id, permissions: defaultPermissions)
        ToastManager.shared.showSuccess(
            title: "Permissions Saved",
            message: "Default permissions for \(device.name) updated."
        )
    }
}

// MARK: - Permission Row Helper

private struct PermissionRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let disabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .disabled(disabled)
                .labelsHidden()
        }
    }
}
