import SwiftUI
import UIKit

@main
struct RemoteDesktopiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            IOSContentView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        ClipboardSyncManager.shared.platformService = IOSClipboardService.shared
        ClipboardSyncManager.shared.startMonitoring()
        return true
    }
}
