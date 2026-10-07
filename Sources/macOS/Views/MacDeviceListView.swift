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

    public init(device: Device, onConnect: @escaping () -> Void) {
        self.device = device
        self.onConnect = onConnect
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: device.platform == .macOS ? "macbook" : "iphone")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            Text(device.name)
                .font(.largeTitle)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Device Capabilities")
                    .font(.headline)

                HStack {
                    Label("Screen Sharing", systemImage: device.capabilities.screenViewing ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(device.capabilities.screenViewing ? .green : .gray)
                    Spacer()
                    Text(device.capabilities.screenViewing ? "Available" : "Unavailable")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("Remote Control", systemImage: device.capabilities.remoteControl ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(device.capabilities.remoteControl ? .green : .orange)
                    Spacer()
                    Text(device.capabilities.remoteControl ? "Available" : "Requires Accessibility")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("Clipboard Sync", systemImage: device.capabilities.clipboard ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(device.capabilities.clipboard ? .green : .gray)
                    Spacer()
                    Text(device.capabilities.clipboard ? "Supported" : "Disabled")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("File Transfer", systemImage: device.capabilities.fileTransfer ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(device.capabilities.fileTransfer ? .green : .gray)
                    Spacer()
                    Text(device.capabilities.fileTransfer ? "Supported" : "Disabled")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .frame(maxWidth: 380)

            Button("Start Session with \(device.name)") {
                onConnect()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(device.onlineState != .online)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
