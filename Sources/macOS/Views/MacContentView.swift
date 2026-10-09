import SwiftUI
import AppKit

// MARK: - Mac Toast Notification System

public enum MacToastType {
    case success
    case info
    case warning
    case error

    public var systemIcon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .success: return .green
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

public struct MacToastItem: Identifiable, Equatable {
    public let id: UUID = UUID()
    public let type: MacToastType
    public let title: String
    public let message: String?
    public let duration: Double

    public init(type: MacToastType, title: String, message: String? = nil, duration: Double = 3.5) {
        self.type = type
        self.title = title
        self.message = message
        self.duration = duration
    }

    public static func == (lhs: MacToastItem, rhs: MacToastItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
public final class MacToastManager: ObservableObject {
    public static let shared = MacToastManager()

    @Published public private(set) var toasts: [MacToastItem] = []

    private init() {}

    public func show(type: MacToastType, title: String, message: String? = nil, duration: Double = 3.5) {
        let toast = MacToastItem(type: type, title: title, message: message, duration: duration)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            toasts.append(toast)
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            self.dismiss(id: toast.id)
        }
    }

    public func showSuccess(title: String, message: String? = nil) {
        show(type: .success, title: title, message: message)
    }

    public func showInfo(title: String, message: String? = nil) {
        show(type: .info, title: title, message: message)
    }

    public func showWarning(title: String, message: String? = nil) {
        show(type: .warning, title: title, message: message)
    }

    public func showError(title: String, message: String? = nil) {
        show(type: .error, title: title, message: message, duration: 4.5)
    }

    public func dismiss(id: UUID) {
        withAnimation(.easeOut(duration: 0.25)) {
            toasts.removeAll { $0.id == id }
        }
    }
}

public struct MacToastCardView: View {
    public let toast: MacToastItem
    public let onDismiss: () -> Void

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: toast.type.systemIcon)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(toast.type.tintColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                if let message = toast.message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 280, maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(toast.type.tintColor.opacity(0.35), lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
        )
    }
}

public struct MacToastOverlayModifier: ViewModifier {
    @ObservedObject var toastManager = MacToastManager.shared

    public func body(content: Content) -> some View {
        ZStack {
            content

            VStack(spacing: 8) {
                ForEach(toastManager.toasts) { toast in
                    MacToastCardView(toast: toast) {
                        toastManager.dismiss(id: toast.id)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
            .zIndex(999)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: toastManager.toasts)
        }
    }
}

public extension View {
    func macToastOverlay() -> some View {
        self.modifier(MacToastOverlayModifier())
    }
}

// MARK: - MacContentView

public struct MacContentView: View {
    @State private var selectedDevice: Device? = nil
    @State private var discoveredDevices: [Device] = []
    @State private var isPairingModalPresented: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var activeControllerViewModel: MacSessionViewModel? = nil
    @State private var activeHostViewModel: MacHostSessionViewModel? = nil
    @State private var isRefreshingDiscovery: Bool = false

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
                    .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 380)
                } detail: {
                    if let device = selectedDevice {
                        MacDeviceDetailView(device: device) {
                            connectToDevice(device)
                        }
                    } else {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                Image(systemName: "desktopcomputer.and.arrow.down")
                                    .font(.system(size: 38))
                                    .foregroundColor(.blue)
                            }

                            VStack(spacing: 6) {
                                Text("Select a Device")
                                    .font(.title2.weight(.bold))
                                    .foregroundColor(.primary)

                                Text("Choose a discovered Mac or iPhone from the sidebar to configure permissions and connect.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 360)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                    }
                }
            }
        }
        .toolbar {
            if activeControllerViewModel == nil && activeHostViewModel == nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isRefreshingDiscovery = true
                        setupBonjourDiscovery()
                        MacToastManager.shared.showInfo(
                            title: "Scanning Network",
                            message: "Broadcasting zero-config Bonjour discovery."
                        )
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            isRefreshingDiscovery = false
                        }
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshingDiscovery ? 360 : 0))
                            .animation(
                                isRefreshingDiscovery ?
                                .linear(duration: 0.8).repeatForever(autoreverses: false) :
                                .default,
                                value: isRefreshingDiscovery
                            )
                    }
                    .help("Rescan local network for Remote Desktop devices")

                    Button {
                        isPairingModalPresented = true
                    } label: {
                        Label("Pair Device", systemImage: "plus.circle.fill")
                    }
                    .help("Pair with a new Mac or iOS device using a secure code")

                    Button {
                        isSettingsPresented = true
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .help("Open Remote Desktop Settings")
                }
            }
        }
        .macToastOverlay()
        .sheet(isPresented: $isPairingModalPresented) {
            MacPairingModalView { newDevice in
                if !self.discoveredDevices.contains(where: { $0.id == newDevice.id }) {
                    self.discoveredDevices.append(newDevice)
                }
                self.selectedDevice = newDevice
                MacToastManager.shared.showSuccess(
                    title: "Device Paired",
                    message: "Successfully paired with \(newDevice.name)."
                )
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            VStack(spacing: 0) {
                HStack {
                    Text("Settings")
                        .font(.headline)
                    Spacer()
                    Button("Done") {
                        isSettingsPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()

                Divider()

                MacSettingsView()
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
                        MacToastManager.shared.showSuccess(
                            title: "Session Approved",
                            message: "Sharing screen with \(requester.name)."
                        )
                        let hostVM = MacHostSessionViewModel(
                            peerName: requester.name,
                            initialPermissions: grantedPermissions
                        )
                        hostVM.onSessionStopped = {
                            DispatchQueue.main.async {
                                self.activeHostViewModel = nil
                                MacToastManager.shared.showInfo(
                                    title: "Session Ended",
                                    message: "Remote host broadcast has ended."
                                )
                            }
                        }
                        self.activeHostViewModel = hostVM
                    } else {
                        MacToastManager.shared.showWarning(
                            title: "Connection Declined",
                            message: "Declined request from \(requester.name)."
                        )
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
                MacToastManager.shared.showInfo(
                    title: "Incoming Request",
                    message: "\(requester.name) is requesting remote access."
                )
            }
        }
    }

    private func connectToDevice(_ device: Device) {
        MacToastManager.shared.showInfo(
            title: "Connecting",
            message: "Establishing session with \(device.name)..."
        )

        let sessionVM = MacSessionViewModel(peerName: device.name, targetDevice: device)
        sessionVM.onDisconnect = { [weak sessionVM] in
            DispatchQueue.main.async {
                if self.activeControllerViewModel === sessionVM {
                    self.activeControllerViewModel = nil
                    MacToastManager.shared.showInfo(
                        title: "Session Closed",
                        message: "Disconnected from \(device.name)."
                    )
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
                MacToastManager.shared.showError(
                    title: "Connection Failed",
                    message: error.localizedDescription
                )
            }
        }
    }
}
