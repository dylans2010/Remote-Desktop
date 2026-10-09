import SwiftUI
import UIKit

// MARK: - Toast Notification System

public enum ToastType: Equatable {
    case success
    case info
    case warning
    case error

    public var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .success: return Color.green
        case .info: return Color.blue
        case .warning: return Color.orange
        case .error: return Color.red
        }
    }
}

public struct ToastItem: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let message: String?
    public let type: ToastType
    public let duration: Double

    public init(id: UUID = UUID(), title: String, message: String? = nil, type: ToastType = .info, duration: Double = 3.2) {
        self.id = id
        self.title = title
        self.message = message
        self.type = type
        self.duration = duration
    }
}

@MainActor
public final class ToastManager: ObservableObject {
    public static let shared = ToastManager()

    @Published public var currentToast: ToastItem? = nil
    private var dismissTask: Task<Void, Never>? = nil

    public func show(title: String, message: String? = nil, type: ToastType = .info, duration: Double = 3.2) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            self.currentToast = ToastItem(title: title, message: message, type: type, duration: duration)
        }
        triggerHaptic(for: type)

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.currentToast = nil
            }
        }
    }

    public func showSuccess(title: String, message: String? = nil) {
        show(title: title, message: message, type: .success)
    }

    public func showInfo(title: String, message: String? = nil) {
        show(title: title, message: message, type: .info)
    }

    public func showWarning(title: String, message: String? = nil) {
        show(title: title, message: message, type: .warning)
    }

    public func showError(title: String, message: String? = nil) {
        show(title: title, message: message, type: .error)
    }

    public func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            self.currentToast = nil
        }
    }

    private func triggerHaptic(for type: ToastType) {
        let generator = UINotificationFeedbackGenerator()
        switch type {
        case .success:
            generator.notificationOccurred(.success)
        case .warning:
            generator.notificationOccurred(.warning)
        case .error:
            generator.notificationOccurred(.error)
        case .info:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

public struct ToastCardView: View {
    public let toast: ToastItem
    public let onDismiss: () -> Void

    public var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 12) {
                Image(systemName: toast.type.iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(toast.type.tintColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    if let message = toast.message, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(toast.type.tintColor.opacity(0.35), lineWidth: 1.2)
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 14, x: 0, y: 6)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

public struct ToastOverlayModifier: ViewModifier {
    @ObservedObject var toastManager = ToastManager.shared

    public func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if let toast = toastManager.currentToast {
                ToastCardView(toast: toast) {
                    toastManager.dismiss()
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                .zIndex(999)
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
        }
    }
}

extension View {
    public func toastOverlay() -> some View {
        self.modifier(ToastOverlayModifier())
    }
}

// MARK: - Root Content View

public struct IOSContentView: View {
    @State private var selectedDevice: Device? = nil
    @State private var discoveredDevices: [Device] = []
    @State private var isPairingModalPresented: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var isRefreshing: Bool = false
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
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                refreshDiscovery()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 15, weight: .semibold))
                                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                    .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                            }
                        }
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            Button {
                                isSettingsPresented = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 16))
                            }

                            Button {
                                isPairingModalPresented = true
                            } label: {
                                Label("Pair", systemImage: "plus.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                    }
                    .navigationDestination(for: Device.self) { device in
                        IOSDeviceDetailView(device: device) {
                            connectToDevice(device)
                        }
                    }
                }
            }
        }
        .toastOverlay()
        .sheet(isPresented: $isPairingModalPresented) {
            IOSPairingModalView { newDevice in
                if !self.discoveredDevices.contains(where: { $0.id == newDevice.id }) {
                    self.discoveredDevices.append(newDevice)
                }
                ToastManager.shared.showSuccess(
                    title: "Device Paired",
                    message: "\(newDevice.name) is now paired and ready to connect."
                )
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                IOSSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                isSettingsPresented = false
                            }
                            .fontWeight(.semibold)
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
                        ToastManager.shared.showSuccess(
                            title: "Session Approved",
                            message: "Sharing screen with \(requester.name)"
                        )
                        let hostVM = IOSHostSessionViewModel(
                            peerName: requester.name,
                            initialPermissions: grantedPermissions
                        )
                        hostVM.onSessionStopped = {
                            DispatchQueue.main.async {
                                self.activeHostViewModel = nil
                                ToastManager.shared.showInfo(
                                    title: "Session Ended",
                                    message: "Screen sharing session was closed."
                                )
                            }
                        }
                        self.activeHostViewModel = hostVM
                    } else {
                        ToastManager.shared.showInfo(
                            title: "Connection Declined",
                            message: "Declined connection request from \(requester.name)"
                        )
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

    private func refreshDiscovery() {
        isRefreshing = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        ToastManager.shared.showInfo(title: "Searching Network", message: "Discovering nearby Macs and devices...")
        setupBonjourDiscovery()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.isRefreshing = false
        }
    }

    private func setupBonjourDiscovery() {
        let localIdentity = DeviceIdentity.current
        BonjourDiscoveryManager.shared.startAdvertising(identity: localIdentity)
        BonjourDiscoveryManager.shared.startBrowsing { devices in
            DispatchQueue.main.async {
                let previousCount = self.discoveredDevices.count
                self.discoveredDevices = devices
                if devices.count > previousCount {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
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
        ToastManager.shared.showInfo(
            title: "Connecting...",
            message: "Establishing secure link with \(device.name)"
        )
        let sessionVM = IOSSessionViewModel(peerName: device.name, targetDevice: device)
        sessionVM.onDisconnect = { [weak sessionVM] in
            DispatchQueue.main.async {
                if self.activeControllerViewModel === sessionVM {
                    self.activeControllerViewModel = nil
                    ToastManager.shared.showInfo(
                        title: "Disconnected",
                        message: "Session with \(device.name) closed."
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
                print("[IOSContentView] Start session encountered error: \(error)")
                await MainActor.run {
                    ToastManager.shared.showError(
                        title: "Connection Failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }
}
