import SwiftUI
import AppKit

@main
struct RemoteDesktopMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MacContentView()
        }
        .windowStyle(.titleBar)

        Settings {
            MacSettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ClipboardSyncManager.shared.platformService = MacClipboardService.shared
        ClipboardSyncManager.shared.startMonitoring()
        HostModeManager.shared.setupStatusItem()
    }
}
