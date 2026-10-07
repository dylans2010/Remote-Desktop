import Foundation
import CoreGraphics

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

/// Display information for local system displays.
public struct DisplayInfo: Identifiable, Codable, Sendable {
    public let id: CGDirectDisplayID
    public let name: String
    public let width: Int
    public let height: Int
    public let isMain: Bool

    public init(id: CGDirectDisplayID, name: String, width: Int, height: Int, isMain: Bool) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.isMain = isMain
    }
}

/// Capture stream configuration parameters.
public struct FrameCaptureConfig: Sendable {
    public var frameRate: Int = 60
    public var targetWidth: Int = 1920
    public var targetHeight: Int = 1080
    public var selectedDisplayID: CGDirectDisplayID?

    public init(frameRate: Int = 60, targetWidth: Int = 1920, targetHeight: Int = 1080, selectedDisplayID: CGDirectDisplayID? = nil) {
        self.frameRate = frameRate
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
        self.selectedDisplayID = selectedDisplayID
    }
}

/// Callback protocol for captured screen frames.
public protocol ScreenCaptureDelegate: AnyObject {
    func screenCaptureEngine(_ engine: ScreenCaptureEngine, didCaptureFrame frameData: Data, timestamp: Double)
    func screenCaptureEngine(_ engine: ScreenCaptureEngine, didEncounterError error: Error)
}

/// Native ScreenCaptureKit capture stream engine.
public final class ScreenCaptureEngine: NSObject, @unchecked Sendable {
    public weak var delegate: ScreenCaptureDelegate?
    private var isCapturing = false
    private let lock = NSLock()

    #if os(macOS) && canImport(ScreenCaptureKit)
    private var stream: SCStream?
    #endif

    public override init() {
        super.init()
    }

    /// Enumerate all connected displays on macOS.
    public static func availableDisplays() async throws -> [DisplayInfo] {
        #if os(macOS) && canImport(ScreenCaptureKit)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays.map { scDisplay in
            DisplayInfo(
                id: scDisplay.displayID,
                name: "Display \(scDisplay.displayID)",
                width: scDisplay.width,
                height: scDisplay.height,
                isMain: scDisplay.displayID == CGMainDisplayID()
            )
        }
        #else
        return [
            DisplayInfo(id: 1, name: "Main Display", width: 1920, height: 1080, isMain: true)
        ]
        #endif
    }

    /// Start capturing screen stream using ScreenCaptureKit.
    public func startCapture(config: FrameCaptureConfig = FrameCaptureConfig()) async throws {
        lock.lock()
        guard !isCapturing else {
            lock.unlock()
            return
        }
        isCapturing = true
        lock.unlock()

        #if os(macOS) && canImport(ScreenCaptureKit)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = config.selectedDisplayID ?? CGMainDisplayID()
        guard let targetDisplay = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw NSError(domain: "ScreenCaptureEngine", code: 404, userInfo: [NSLocalizedDescriptionKey: "No display available for capture"])
        }

        let filter = SCContentFilter(display: targetDisplay, excludingApplications: [], exceptingWindows: [])
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = config.targetWidth
        streamConfig.height = config.targetHeight
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.frameRate))
        streamConfig.queueDepth = 5
        streamConfig.showsCursor = true

        let scStream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try await scStream.startCapture()

        lock.lock()
        self.stream = scStream
        lock.unlock()
        print("[ScreenCaptureEngine] Started ScreenCaptureKit stream at \(config.frameRate) FPS (\(config.targetWidth)x\(config.targetHeight))")
        #else
        print("[ScreenCaptureEngine] Simulated capture active on non-macOS target")
        #endif
    }

    /// Stop current capture session.
    public func stopCapture() async {
        lock.lock()
        defer { lock.unlock() }

        guard isCapturing else { return }
        isCapturing = false

        #if os(macOS) && canImport(ScreenCaptureKit)
        if let scStream = stream {
            try? await scStream.stopCapture()
            self.stream = nil
        }
        #endif
        print("[ScreenCaptureEngine] Screen capture stopped")
    }
}

#if os(macOS) && canImport(ScreenCaptureKit)
extension ScreenCaptureEngine: SCStreamOutput {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // Convert CVImageBuffer to CGImage / Data payload
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        #if os(macOS)
        let nsBitmap = NSBitmapImageRep(cgImage: cgImage)
        if let jpegData = nsBitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) {
            delegate?.screenCaptureEngine(self, didCaptureFrame: jpegData, timestamp: timeStamp)
        }
        #endif
    }
}
#endif
