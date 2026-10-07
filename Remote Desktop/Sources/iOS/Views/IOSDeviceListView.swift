import SwiftUI

public struct IOSDeviceListView: View {
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
        List {
            Section(header: Text("Discovered & Paired Devices")) {
                if devices.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Nearby Devices")
                            .font(.headline)
                        Text("Tap 'Pair Device' or ensure Remote Desktop is open on your Mac.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(devices) { device in
                        NavigationLink(value: device) {
                            HStack(spacing: 12) {
                                Image(systemName: device.platform == .macOS ? "macbook" : "iphone")
                                    .font(.title2)
                                    .foregroundColor(device.onlineState == .online ? .blue : .gray)

                                VStack(alignment: .leading, spacing: 4) {
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
                        }
                    }
                }
            }

            Section(header: Text("This iPhone Screen Broadcast")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Broadcast Screen to Mac")
                        .font(.headline)
                    Text("Use Apple's ReplayKit broadcast extension to share this iPhone screen to a connected Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        BroadcastPickerView(preferredExtensionBundleID: "com.dylans2010.RemoteDesktop.BroadcastExtension")
                            .frame(width: 44, height: 44)
                        Text("Tap to Start Broadcast")
                            .font(.callout)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onPairClicked) {
                    Label("Pair", systemImage: "plus")
                }
            }
        }
    }
}

public struct IOSDeviceDetailView: View {
    let device: Device
    var onConnect: () -> Void

    public init(device: Device, onConnect: @escaping () -> Void) {
        self.device = device
        self.onConnect = onConnect
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: device.platform == .macOS ? "macbook" : "iphone")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                    .padding(.top, 20)

                Text(device.name)
                    .font(.title)
                    .bold()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Remote Capabilities")
                        .font(.headline)

                    HStack {
                        Label("Screen Viewing", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Spacer()
                        Text("Supported")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Remote Control", systemImage: device.platform == .macOS ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundColor(device.platform == .macOS ? .green : .gray)
                        Spacer()
                        Text(device.platform == .macOS ? "Supported" : "Unavailable on iOS")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Clipboard Sync", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Spacer()
                        Text("Supported")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("File Transfer", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Spacer()
                        Text("Supported")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                Button(action: onConnect) {
                    Text("Connect to \(device.name)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(device.onlineState == .online ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(device.onlineState != .online)
                .padding(.horizontal)
            }
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
