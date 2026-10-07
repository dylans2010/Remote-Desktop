import Foundation
import CoreGraphics
import AppKit

/// Display enumerator for macOS system displays.
public final class DisplayManager: @unchecked Sendable {
    public static let shared = DisplayManager()

    private init() {}

    /// Retrieve active displays on this Mac.
    public func getDisplays() -> [DisplayInfo] {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)

        guard displayCount > 0 else { return [] }

        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &activeDisplays, &displayCount)

        let mainID = CGMainDisplayID()

        return activeDisplays.enumerated().map { index, displayID in
            let bounds = CGDisplayBounds(displayID)
            let width = Int(bounds.width)
            let height = Int(bounds.height)
            let isMain = (displayID == mainID)
            let name = isMain ? "Main Display (\(width)x\(height))" : "Display \(index + 1) (\(width)x\(height))"
            return DisplayInfo(id: displayID, name: name, width: width, height: height, isMain: isMain)
        }
    }
}
