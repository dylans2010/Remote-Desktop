import SwiftUI

public struct IOSContentView: View {
    @State private var selectedDevice: Device? = nil
    @State private var discoveredDevices: [Device] = []
    @State private var isPairingModalPresented: Bool = false
    @State private var activeSessionViewModel: IOSSessionViewModel? = nil

    public init() {}

    public var body: some View {
        Group {
            if let sessionVM = activeSessionViewModel {
                IOSSessionViewerView(viewModel: sessionVM)
            } else {
                NavigationStack {
                    IOSDeviceListView(
                        selectedDevice: $selectedDevice,
                        devices: discoveredDevices,
                        onConnect: { device in
                            connectToDevice(device)
                        },
                        onPairClicked: {
                            isPairingModalPresented = true
                        }
                    )
                    .navigationTitle("Remote Desktop")
                    .navigationDestination(for: Device.self) { device in
                        IOSDeviceDetailView(device: device) {
                            connectToDevice(device)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isPairingModalPresented) {
            IOSPairingModalView { code in
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
        }
    }

    private func setupBonjourDiscovery() {
        let localIdentity = DeviceIdentity(deviceName: "iPhone")
        BonjourDiscoveryManager.shared.startAdvertising(identity: localIdentity)
        BonjourDiscoveryManager.shared.startBrowsing { devices in
            DispatchQueue.main.async {
                self.discoveredDevices = devices
            }
        }
    }

    private func connectToDevice(_ device: Device) {
        let sessionVM = IOSSessionViewModel(peerName: device.name)
        sessionVM.onDisconnect = { [weak sessionVM] in
            DispatchQueue.main.async {
                if self.activeSessionViewModel === sessionVM {
                    self.activeSessionViewModel = nil
                }
            }
        }
        self.activeSessionViewModel = sessionVM

        Task {
            do {
                try await RemoteSessionManager.shared.startSession(with: device)
            } catch {
                print("[IOSContentView] Failed to connect: \(error)")
                DispatchQueue.main.async {
                    self.activeSessionViewModel = nil
                }
            }
        }
    }
}
