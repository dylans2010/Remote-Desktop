import Foundation
import CoreGraphics

/// Display geometry management and screen layout calculations for multi-monitor setups.
public final class DisplayManager: @unchecked Sendable {
    public static let shared = DisplayManager()

    private var displays: [DisplayInfo] = []
    private var selectedDisplayIndex: Int = 0
    private let lock = NSLock()

    private init() {
        refreshDisplays()
    }

    /// Refresh known local display configurations.
    public func refreshDisplays() {
        Task {
            if let available = try? await ScreenCaptureEngine.availableDisplays() {
                self.lock.lock()
                self.displays = available
                self.lock.unlock()
            }
        }
    }

    /// Returns list of available displays.
    public var currentDisplays: [DisplayInfo] {
        lock.lock()
        defer { lock.unlock() }
        return displays
    }

    /// Selected active display index.
    public var activeDisplayIndex: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return selectedDisplayIndex
        }
        set {
            lock.lock()
            selectedDisplayIndex = newValue
            lock.unlock()
        }
    }

    /// Currently active display information.
    public var activeDisplay: DisplayInfo? {
        lock.lock()
        defer { lock.unlock() }
        guard selectedDisplayIndex >= 0 && selectedDisplayIndex < displays.count else {
            return displays.first
        }
        return displays[selectedDisplayIndex]
    }
}
