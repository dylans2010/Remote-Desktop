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
        if CommandLine.arguments.contains("--test") {
            let success = RemoteDesktopUnitTests.runAllTests()
            exit(success ? 0 : 1)
        }
        _ = RemoteDesktopUnitTests.runAllTests()
        ClipboardSyncManager.shared.platformService = MacClipboardService.shared
        ClipboardSyncManager.shared.startMonitoring()
        HostModeManager.shared.setupStatusItem()
    }
}
