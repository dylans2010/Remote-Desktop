import SwiftUI

public struct DeviceListView: View {
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
                    Text("Ensure another Mac is running Remote Desktop on the local network or click Pair Computer.")
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
