import SwiftUI

public struct MacContentView: View {
    @State private var selectedDevice: Device? = nil
    @State private var discoveredDevices: [Device] = []
    @State private var isPairingModalPresented: Bool = false
    @State private var activeControllerViewModel: MacSessionViewModel? = nil
    @State private var activeHostViewModel: MacHostSessionViewModel? = nil

    // Pending incoming request state
    @State private var pendingIncomingRequester: Device? = nil
    @State private var pendingRequestedPermissions: RemoteSessionPermissions = .standardDefault
    @State private var pendingDecisionCallback: ((Bool, RemoteSessionPermissions) -> Void)? = nil

    public init() {}

    public var body: some View {
        Group {
            if let controllerVM = activeControllerViewModel {
                // View 1: CONTROLLER VIEW (Viewer looking at remote machine)
                MacSessionViewerView(viewModel: controllerVM)
            } else if let hostVM = activeHostViewModel {
                // View 2: HOST VIEW (This machine being viewed/controlled)
                MacHostSessionView(viewModel: hostVM)
            } else {
                // View 3: IDLE DEVICE MANAGEMENT
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
            MacPairingModalView { newDevice in
                if !self.discoveredDevices.contains(where: { $0.id == newDevice.id }) {
                    self.discoveredDevices.append(newDevice)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingIncomingRequester != nil },
            set: { if !$0 { pendingIncomingRequester = nil } }
        )) {
            if let requester = pendingIncomingRequester {
                MacIncomingRequestSheet(
                    requester: requester,
                    initialPermissions: pendingRequestedPermissions
                ) { approved, grantedPermissions in
                    pendingIncomingRequester = nil
                    pendingDecisionCallback?(approved, grantedPermissions)
                    pendingDecisionCallback = nil

                    if approved {
                        let hostVM = MacHostSessionViewModel(
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
            MacNotificationManager.shared.requestAuthorization()
            setupBonjourDiscovery()
            setupIncomingApprovalHandler()
        }
    }

    private func setupBonjourDiscovery() {
        let localIdentity = DeviceIdentity.current
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

                let permSummary = requestedPermissions.controlScreen ? "View screen & control input" : "View screen only"
                MacNotificationManager.shared.notifyIncomingConnection(
                    peerName: requester.name,
                    permissionsDescription: permSummary
                )
            }
        }
    }

    private func connectToDevice(_ device: Device) {
        let sessionVM = MacSessionViewModel(peerName: device.name, targetDevice: device)
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
                print("[MacContentView] Start session encountered error: \(error)")
                // Do NOT dismiss activeControllerViewModel on error!
                // The session view model remains active and displays the actionable error state.
            }
        }
    }
}
