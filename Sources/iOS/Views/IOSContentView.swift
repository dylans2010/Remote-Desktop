import SwiftUI

public struct IOSContentView: View {
    @State private var selectedDevice: Device? = nil
    @State private var discoveredDevices: [Device] = []
    @State private var isPairingModalPresented: Bool = false
    @State private var activeControllerViewModel: IOSSessionViewModel? = nil
    @State private var activeHostViewModel: IOSHostSessionViewModel? = nil

    @State private var pendingIncomingRequester: Device? = nil
    @State private var pendingRequestedPermissions: RemoteSessionPermissions = .standardDefault
    @State private var pendingDecisionCallback: ((Bool, RemoteSessionPermissions) -> Void)? = nil

    public init() {}

    public var body: some View {
        Group {
            if let controllerVM = activeControllerViewModel {
                IOSSessionViewerView(viewModel: controllerVM)
            } else if let hostVM = activeHostViewModel {
                IOSHostSessionView(viewModel: hostVM)
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
        .sheet(isPresented: Binding(
            get: { pendingIncomingRequester != nil },
            set: { if !$0 { pendingIncomingRequester = nil } }
        )) {
            if let requester = pendingIncomingRequester {
                IOSIncomingRequestSheet(
                    requester: requester,
                    initialPermissions: pendingRequestedPermissions
                ) { approved, grantedPermissions in
                    pendingIncomingRequester = nil
                    pendingDecisionCallback?(approved, grantedPermissions)
                    pendingDecisionCallback = nil

                    if approved {
                        let hostVM = IOSHostSessionViewModel(
                            peerName: requester.name,
                            initialPermissions: grantedPermissions
                        )
                        hostVM.onSessionStopped = {
                            DispatchQueue.main.async {
                                self.activeHostViewModel = nil
                            }
                        }
                        self.activeHostViewModel = hostVM
                    }
                }
            }
        }
        .onAppear {
            IOSNotificationManager.shared.requestAuthorization()
            setupBonjourDiscovery()
            setupIncomingApprovalHandler()
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

    private func setupIncomingApprovalHandler() {
        RemoteSessionManager.shared.incomingApprovalHandler = { requester, requestedPermissions, decisionCallback in
            DispatchQueue.main.async {
                self.pendingIncomingRequester = requester
                self.pendingRequestedPermissions = requestedPermissions
                self.pendingDecisionCallback = decisionCallback

                IOSNotificationManager.shared.notifyIncomingConnection(
                    peerName: requester.name,
                    permissionsDescription: "View Screen"
                )
            }
        }
    }

    private func connectToDevice(_ device: Device) {
        let sessionVM = IOSSessionViewModel(peerName: device.name)
        sessionVM.onDisconnect = { [weak sessionVM] in
            DispatchQueue.main.async {
                if self.activeControllerViewModel === sessionVM {
                    self.activeControllerViewModel = nil
                }
            }
        }
        self.activeControllerViewModel = sessionVM

        let initialPermissions = TrustModel.shared.defaultPermissions(for: device.id)

        Task {
            do {
                try await RemoteSessionManager.shared.startSession(with: device, requestedPermissions: initialPermissions)
            } catch {
                print("[IOSContentView] Failed to connect: \(error)")
                DispatchQueue.main.async {
                    self.activeControllerViewModel = nil
                }
            }
        }
    }
}
