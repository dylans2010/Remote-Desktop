import SwiftUI

public struct MacContentView: View {
    @State private var selectedDevice: Device? = nil
    @State private var discoveredDevices: [Device] = []
    @State private var isPairingModalPresented: Bool = false
    @State private var activeSessionViewModel: MacSessionViewModel? = nil
    @State private var incomingRequestPeer: Device? = nil

    public init() {}

    public var body: some View {
        Group {
            if let sessionVM = activeSessionViewModel {
                MacSessionViewerView(viewModel: sessionVM)
            } else {
                NavigationSplitView {
                    MacDeviceListView(
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
                        MacDeviceDetailView(device: device) {
                            connectToDevice(device)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Select a device to view details")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isPairingModalPresented) {
            MacPairingModalView { code in
                PairingManager.shared.pairWithDevice(using: code) { success, peer in
                    if success, let peer = peer {
                        TrustModel.shared.trustDevice(peer)
                        self.discoveredDevices.append(peer)
                    }
                }
            }
        }
        .onAppear {
            setupBonjourDiscovery()
            HostModeManager.shared.onRequestIncomingConnection = { peer, completion in
                self.incomingRequestPeer = peer
                // Handle alert/approval prompt
                completion(true)
            }
        }
    }

    private func setupBonjourDiscovery() {
        let localIdentity = DeviceIdentity(deviceName: Host.current().localizedName ?? "Mac")
        BonjourDiscoveryManager.shared.startAdvertising(identity: localIdentity)
        BonjourDiscoveryManager.shared.startBrowsing { devices in
            DispatchQueue.main.async {
                self.discoveredDevices = devices
            }
        }
    }

    private func connectToDevice(_ device: Device) {
        guard ScreenRecordingPermissionManager.shared.isAuthorized else {
            ScreenRecordingPermissionManager.shared.requestPermission()
            return
        }

        let sessionVM = MacSessionViewModel(peerName: device.name)
        self.activeSessionViewModel = sessionVM

        Task {
            do {
                try await RemoteSessionManager.shared.startSession(with: device)
            } catch {
                print("[MacContentView] Failed to connect: \(error)")
                DispatchQueue.main.async {
                    self.activeSessionViewModel = nil
                }
            }
        }
    }
}
