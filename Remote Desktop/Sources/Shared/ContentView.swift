import SwiftUI

struct ContentView: View {
    @State private var selectedDevice: Device? = nil
    @State private var discoveredDevices: [Device] = []
    @State private var isPairingModalPresented: Bool = false
    @State private var activeSessionViewModel: SessionViewModel? = nil
    @State private var incomingRequestPeer: Device? = nil
    @State private var incomingCompletion: ((Bool) -> Void)? = nil

    var body: some View {
        Group {
            if let sessionVM = activeSessionViewModel {
                SessionViewerView(viewModel: sessionVM)
            } else {
                NavigationSplitView {
                    DeviceListView(
                        selectedDevice: $selectedDevice,
                        devices: discoveredDevices,
                        onConnect: { device in
                            connectToDevice(device)
                        },
                        onPairClicked: {
                            isPairingModalPresented = true
                        }
                    )
                } detail: {
                    if let device = selectedDevice {
                        DeviceDetailView(device: device) {
                            connectToDevice(device)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Select a device to initiate Remote Desktop")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isPairingModalPresented) {
            PairingModalView { code in
                print("[ContentView] Pairing code submitted: \(code)")
            }
        }
        .alert(item: $incomingRequestPeer) { peer in
            Alert(
                title: Text("Incoming Connection Request"),
                message: Text("\(peer.name) wants to view and control this Mac remotely."),
                primaryButton: .default(Text("Allow")) {
                    incomingCompletion?(true)
                },
                secondaryButton: .destructive(Text("Decline")) {
                    incomingCompletion?(false)
                }
            )
        }
        .onAppear {
            setupApp()
        }
    }

    private func setupApp() {
        let identity = DeviceIdentity()
        HostModeManager.shared.startHostService(identity: identity)

        HostModeManager.shared.onRequestIncomingConnection = { peer, completion in
            DispatchQueue.main.async {
                self.incomingRequestPeer = peer
                self.incomingCompletion = completion
            }
        }

        // Start Bonjour discovery
        let discovery = BonjourDiscoveryManager()
        discovery.onPeerDiscovered = { device in
            DispatchQueue.main.async {
                if !self.discoveredDevices.contains(where: { $0.id == device.id }) {
                    self.discoveredDevices.append(device)
                }
            }
        }
        discovery.startBrowsing()
    }

    private func connectToDevice(_ device: Device) {
        let vm = SessionViewModel(peerName: device.name)
        activeSessionViewModel = vm
        Task {
            try? await RemoteSessionManager.shared.startSession(with: device)
        }
    }
}

struct DeviceDetailView: View {
    var device: Device
    var onConnect: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: device.platform == .macOS ? "macbook" : "iphone")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            Text(device.name)
                .font(.title)
                .bold()

            HStack(spacing: 8) {
                Circle()
                    .fill(device.onlineState == .online ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(device.onlineState.rawValue.capitalized)
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Device ID:").bold()
                    Text(device.id).font(.system(.caption, design: .monospaced))
                }
                HStack {
                    Text("Platform:").bold()
                    Text(device.platform.rawValue)
                }
                HStack {
                    Text("Trust Status:").bold()
                    Text(device.trustStatus.rawValue.capitalized)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            Button("Connect Remote Session") {
                onConnect()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(32)
    }
}

#Preview {
    ContentView()
}
