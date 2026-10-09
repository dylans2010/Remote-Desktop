import SwiftUI
import AppKit

public struct MacDeviceListView: View {
    @Binding var selectedDevice: Device?
    var devices: [Device]
    var onConnect: (Device) -> Void
    var onPairClicked: () -> Void

    @State private var filterSelection: Int = 0 // 0: All, 1: Macs, 2: iOS
    @State private var searchText: String = ""
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
        devices.filter { device in
            let matchesFilter: Bool
            switch filterSelection {
            case 1: matchesFilter = device.platform == .macOS
            case 2: matchesFilter = device.platform == .iOS || device.platform == .iPadOS
            default: matchesFilter = true
            }

            if searchText.isEmpty {
                return matchesFilter
            } else {
                let query = searchText.lowercased()
                let nameMatches = device.name.lowercased().contains(query)
                let ipMatches = (device.ipAddress ?? "").lowercased().contains(query)
                return matchesFilter && (nameMatches || ipMatches)
            }
        }
    }

    private var trustedDevices: [Device] {
        filteredDevices.filter { TrustModel.shared.isTrusted(deviceID: $0.id) }
    }

    private var nearbyDevices: [Device] {
        filteredDevices.filter { !TrustModel.shared.isTrusted(deviceID: $0.id) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Modern Discovery Hub Header
            MacDiscoveryHeader(
                pulseAnimation: $pulseAnimation,
                onlineCount: devices.filter { $0.onlineState == .online }.count,
                onPairClicked: onPairClicked
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Search & Segmented Filter Bar
            VStack(spacing: 6) {
                // Search Input Box
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField("Search devices or IP...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                )

                // Segmented Filter
                Picker("Filter", selection: $filterSelection) {
                    Text("All (\(devices.count))").tag(0)
                    Text("Macs (\(devices.filter { $0.platform == .macOS }.count))").tag(1)
                    Text("iOS (\(devices.filter { $0.platform != .macOS }.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Device List Content
            if devices.isEmpty {
                MacEmptyDevicesCard(onPairClicked: onPairClicked)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else if filteredDevices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No matching devices")
                        .font(.subheadline.weight(.semibold))
                    Text("No devices match '\(searchText)'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedDevice) {
                    if !trustedDevices.isEmpty {
                        Section {
                            ForEach(trustedDevices, id: \.id) { device in
                                MacDeviceRowCard(
                                    device: device,
                                    isSelected: selectedDevice?.id == device.id,
                                    onConnect: { onConnect(device) }
                                )
                                .tag(device)
                                .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
                                .simultaneousGesture(TapGesture(count: 2).onEnded {
                                    onConnect(device)
                                })
                            }
                        } header: {
                            HStack {
                                Text("TRUSTED DEVICES")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(trustedDevices.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }

                    if !nearbyDevices.isEmpty {
                        Section {
                            ForEach(nearbyDevices, id: \.id) { device in
                                MacDeviceRowCard(
                                    device: device,
                                    isSelected: selectedDevice?.id == device.id,
                                    onConnect: { onConnect(device) }
                                )
                                .tag(device)
                                .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
                                .simultaneousGesture(TapGesture(count: 2).onEnded {
                                    onConnect(device)
                                })
                            }
                        } header: {
                            HStack {
                                Text("NEARBY ON LOCAL NETWORK")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(nearbyDevices.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()

            // Modern Sidebar Footer
            MacSidebarFooter(onPairClicked: onPairClicked)
        }
        .onAppear {
            pulseAnimation = true
        }
    }
}

// MARK: - Modern Discovery Header

private struct MacDiscoveryHeader: View {
    @Binding var pulseAnimation: Bool
    let onlineCount: Int
    let onPairClicked: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Animated Radar Beacon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 34, height: 34)

                Circle()
                    .stroke(Color.blue.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 34, height: 34)
                    .scaleEffect(pulseAnimation ? 1.2 : 0.95)
                    .opacity(pulseAnimation ? 0.3 : 0.8)
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("Bonjour Mesh")
                        .font(.system(size: 12, weight: .bold))
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                }

                Text("Auto-discovery active")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if onlineCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                    Text("\(onlineCount) online")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.15))
                .foregroundColor(.green)
                .clipShape(Capsule())
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Modern Device Row Card

private struct MacDeviceRowCard: View {
    let device: Device
    let isSelected: Bool
    let onConnect: () -> Void

    @State private var isHovered: Bool = false

    private var isTrusted: Bool {
        TrustModel.shared.isTrusted(deviceID: device.id)
    }

    private var platformGradient: LinearGradient {
        if device.platform == .macOS {
            return LinearGradient(
                colors: [Color.blue, Color(red: 0.2, green: 0.35, blue: 0.9)],
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
        case .macOS: return "macbook"
        case .iOS: return "iphone"
        case .iPadOS: return "ipad"
        case .unknown: return "desktopcomputer"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Squircle Platform Avatar
            ZStack {
                platformGradient
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: Color.blue.opacity(0.2), radius: 3, x: 0, y: 1.5)

                Image(systemName: platformIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            // Info Column
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if isTrusted {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                            .help("Trusted Device")
                    }
                }

                HStack(spacing: 5) {
                    // Pulsing presence beacon
                    ZStack {
                        if device.onlineState == .online {
                            Circle()
                                .fill(Color.green.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                        Circle()
                            .fill(device.onlineState == .online ? Color.green : Color.gray)
                            .frame(width: 5, height: 5)
                    }

                    Text(device.onlineState.rawValue.capitalized)
                        .font(.system(size: 10))
                        .foregroundColor(device.onlineState == .online ? .primary : .secondary)

                    if let ip = device.ipAddress, !ip.isEmpty {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text(ip)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Quick Connect Button (Appears distinctly when online)
            if device.onlineState == .online {
                Button(action: onConnect) {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                        Text("Connect")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(isHovered ? Color.blue : Color.blue.opacity(0.88))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: isHovered ? Color.blue.opacity(0.35) : Color.clear, radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .help("Start session with \(device.name)")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                onConnect()
            } label: {
                Label("Connect to \(device.name)", systemImage: "bolt.fill")
            }
            .disabled(device.onlineState != .online)

            if let ip = device.ipAddress {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ip, forType: .string)
                    MacToastManager.shared.showSuccess(title: "IP Copied", message: ip)
                } label: {
                    Label("Copy IP Address", systemImage: "doc.on.clipboard")
                }
            }

            Divider()

            if isTrusted {
                Button(role: .destructive) {
                    TrustModel.shared.revokeDevice(deviceID: device.id)
                    MacToastManager.shared.showWarning(title: "Trust Revoked", message: "\(device.name) is no longer trusted.")
                } label: {
                    Label("Revoke Trust", systemImage: "xmark.shield")
                }
            }
        }
    }
}

// MARK: - Modern Sidebar Footer

private struct MacSidebarFooter: View {
    let onPairClicked: () -> Void

    private var localName: String {
        DeviceIdentity.current.deviceName
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    Text("This Mac")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(localName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                onPairClicked()
            } label: {
                Label("Pair", systemImage: "plus.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Pair with a new remote device")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
    }
}

// MARK: - Modern Empty Devices Card

private struct MacEmptyDevicesCard: View {
    let onPairClicked: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 64, height: 64)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 26))
                    .foregroundColor(.blue)
            }

            VStack(spacing: 6) {
                Text("Searching for Devices")
                    .font(.system(size: 14, weight: .bold))

                Text("Make sure Remote Desktop is open on your other Mac or iPhone on this Wi-Fi network.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Button {
                onPairClicked()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                    Text("Pair Device with Code")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

// MARK: - Mac Device Detail View

public struct MacDeviceDetailView: View {
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
                // Hero Device Card
                VStack(spacing: 12) {
                    ZStack {
                        LinearGradient(
                            colors: device.platform == .macOS ? [Color.blue, Color.indigo] : [Color.teal, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)

                        Image(systemName: platformIcon)
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.white)
                    }

                    VStack(spacing: 4) {
                        Text(device.name)
                            .font(.title2.weight(.bold))

                        HStack(spacing: 8) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(device.onlineState == .online ? Color.green : Color.gray)
                                    .frame(width: 7, height: 7)
                                Text(device.onlineState.rawValue.capitalized)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(device.onlineState == .online ? .green : .secondary)
                            }

                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text(device.platform.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let ip = device.ipAddress, !ip.isEmpty {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(ip)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Trust Pill
                    HStack(spacing: 6) {
                        Image(systemName: isTrusted ? "checkmark.shield.fill" : "shield.slash.fill")
                            .foregroundColor(isTrusted ? .green : .secondary)
                        Text(isTrusted ? "Trusted Device (Fast Connect)" : "Untrusted Device (Manual Approval Required)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(isTrusted ? .green : .secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(isTrusted ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .padding(.horizontal, 24)

                // Permissions Card
                VStack(alignment: .leading, spacing: 14) {
                    Label("Default Session Permissions", systemImage: "slider.horizontal.3")
                        .font(.headline)

                    VStack(spacing: 12) {
                        MacPermissionRow(
                            icon: "display",
                            color: .blue,
                            title: "Screen Viewing",
                            subtitle: "View high-definition live display stream",
                            isOn: .constant(true),
                            disabled: true
                        )

                        Divider()

                        MacPermissionRow(
                            icon: "cursorarrow.rays",
                            color: .green,
                            title: "Remote Mouse Control",
                            subtitle: "Send mouse cursor movement and clicks",
                            isOn: $defaultPermissions.mouse,
                            disabled: false
                        )
                        .onChange(of: defaultPermissions.mouse) { _, val in
                            if val { defaultPermissions.controlScreen = true }
                            saveDefaults()
                        }

                        Divider()

                        MacPermissionRow(
                            icon: "keyboard",
                            color: .indigo,
                            title: "Remote Keyboard Control",
                            subtitle: "Inject keyboard keystrokes and shortcuts",
                            isOn: $defaultPermissions.keyboard,
                            disabled: false
                        )
                        .onChange(of: defaultPermissions.keyboard) { _, val in
                            if val { defaultPermissions.controlScreen = true }
                            saveDefaults()
                        }

                        Divider()

                        MacPermissionRow(
                            icon: "pencil.tip.crop.circle.badge.plus",
                            color: .purple,
                            title: "Drawing & Annotations",
                            subtitle: "Draw non-destructive visual markup on remote screen",
                            isOn: $defaultPermissions.annotation,
                            disabled: false
                        )
                        .onChange(of: defaultPermissions.annotation) { _, _ in
                            saveDefaults()
                        }

                        Divider()

                        MacPermissionRow(
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

                        Divider()

                        MacPermissionRow(
                            icon: "folder.badge.gearshape",
                            color: .teal,
                            title: "File Transfer",
                            subtitle: "Allow sending and receiving files over encrypted channel",
                            isOn: $defaultPermissions.fileTransfer,
                            disabled: false
                        )
                        .onChange(of: defaultPermissions.fileTransfer) { _, _ in
                            saveDefaults()
                        }
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .padding(.horizontal, 24)

                // Actions
                HStack(spacing: 16) {
                    Button(action: onConnect) {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                            Text("Start Remote Session with \(device.name)")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            device.onlineState == .online ?
                            LinearGradient(colors: [Color.blue, Color(red: 0.15, green: 0.35, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                            LinearGradient(colors: [Color.gray, Color.gray.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: device.onlineState == .online ? Color.blue.opacity(0.3) : Color.clear, radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(device.onlineState != .online)

                    if isTrusted {
                        Button {
                            showingRevokeConfirmation = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.shield.fill")
                                Text("Revoke Trust")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.12))
                            .foregroundColor(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog("Revoke Trust for \(device.name)?", isPresented: $showingRevokeConfirmation, titleVisibility: .visible) {
                            Button("Revoke Trust", role: .destructive) {
                                TrustModel.shared.revokeDevice(deviceID: device.id)
                                isTrusted = false
                                MacToastManager.shared.showWarning(
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
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .padding(.top, 14)
        }
    }

    private func saveDefaults() {
        TrustModel.shared.updateDefaultPermissions(for: device.id, permissions: defaultPermissions)
        MacToastManager.shared.showSuccess(
            title: "Permissions Saved",
            message: "Default permissions for \(device.name) updated."
        )
    }
}

// MARK: - Mac Permission Row Helper

private struct MacPermissionRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let disabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
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
