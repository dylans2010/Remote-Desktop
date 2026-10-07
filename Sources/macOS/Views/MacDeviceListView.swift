import SwiftUI
import AppKit

public struct MacDeviceListView: View {
    @Binding var selectedDevice: Device?
    var devices: [Device]
    var onConnect: (Device) -> Void
    var onPairClicked: () -> Void

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

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("My Devices")
                    .font(.headline)
                    .padding(.leading)
                Spacer()
                Button(action: onPairClicked) {
                    Label("Pair Computer", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.trailing)
            }
            .frame(height: 40)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if devices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No Devices Found")
                        .font(.title3)
                        .bold()
                    Text("Ensure another Mac or iOS device is running Remote Desktop on the local network or click Pair Computer.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(devices, id: \.id, selection: $selectedDevice) { device in
                    HStack {
                        Image(systemName: device.platform == .macOS ? "macbook" : "iphone")
                            .font(.title2)
                            .foregroundColor(device.onlineState == .online ? .blue : .gray)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.body)
                                .bold()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(device.onlineState == .online ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(device.onlineState.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if device.onlineState == .online {
                            Button("Connect") {
                                onConnect(device)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.sidebar)
            }
        }
    }
}

public struct MacDeviceDetailView: View {
    let device: Device
    var onConnect: () -> Void
    @State private var defaultPermissions: RemoteSessionPermissions
    @State private var isTrusted: Bool

    public init(device: Device, onConnect: @escaping () -> Void) {
        self.device = device
        self.onConnect = onConnect
        self._defaultPermissions = State(initialValue: TrustModel.shared.defaultPermissions(for: device.id))
        self._isTrusted = State(initialValue: TrustModel.shared.isTrusted(deviceID: device.id))
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: device.platform == .macOS ? "macbook" : "iphone")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)

                VStack(spacing: 4) {
                    Text(device.name)
                        .font(.largeTitle)
                        .bold()

                    HStack(spacing: 6) {
                        Image(systemName: isTrusted ? "checkmark.shield.fill" : "shield.slash")
                            .foregroundColor(isTrusted ? .green : .secondary)
                        Text(isTrusted ? "Trusted Device" : "Untrusted Device")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Default Access Settings (Req 37 & 38)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Default Access Permissions")
                        .font(.headline)

                    Toggle("Screen Viewing", isOn: $defaultPermissions.viewScreen)
                        .disabled(true)

                    Toggle("Remote Mouse Control", isOn: $defaultPermissions.mouse)
                        .onChange(of: defaultPermissions.mouse) { _, val in
                            if val { defaultPermissions.controlScreen = true }
                            saveDefaults()
                        }

                    Toggle("Remote Keyboard Control", isOn: $defaultPermissions.keyboard)
                        .onChange(of: defaultPermissions.keyboard) { _, val in
                            if val { defaultPermissions.controlScreen = true }
                            saveDefaults()
                        }

                    Toggle("Annotations & Drawing", isOn: $defaultPermissions.annotation)
                        .onChange(of: defaultPermissions.annotation) { _, _ in saveDefaults() }

                    Toggle("Clipboard Synchronization", isOn: $defaultPermissions.clipboard)
                        .onChange(of: defaultPermissions.clipboard) { _, _ in saveDefaults() }

                    Toggle("File Transfer", isOn: $defaultPermissions.fileTransfer)
                        .onChange(of: defaultPermissions.fileTransfer) { _, _ in saveDefaults() }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .frame(maxWidth: 420)

                HStack(spacing: 16) {
                    Button("Start Session with \(device.name)") {
                        onConnect()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(device.onlineState != .online)

                    if isTrusted {
                        Button("Revoke Trust") {
                            TrustModel.shared.revokeDevice(deviceID: device.id)
                            isTrusted = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .foregroundColor(.red)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func saveDefaults() {
        TrustModel.shared.updateDefaultPermissions(for: device.id, permissions: defaultPermissions)
    }
}
