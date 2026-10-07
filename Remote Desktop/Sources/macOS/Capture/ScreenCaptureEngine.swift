import Foundation
import CoreGraphics
import ScreenCaptureKit

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
public protocol FrameCaptureDelegate: AnyObject {
    func frameCaptureEngine(_ engine: ScreenCaptureEngine, didCaptureFrame frameData: Data, timestamp: Double)
}

/// Screen capture engine for macOS using ScreenCaptureKit.
public final class ScreenCaptureEngine: NSObject, SCStreamOutput, @unchecked Sendable {
    public weak var delegate: FrameCaptureDelegate?

    private var stream: SCStream?
    private var isCapturing: Bool = false
    private let lock = NSLock()

    public override init() {
        super.init()
    }

    /// Start capturing display stream using ScreenCaptureKit.
    public func startCapture(config: FrameCaptureConfig = FrameCaptureConfig()) async throws {
        guard ScreenRecordingPermissionManager.shared.isAuthorized else {
            throw NSError(domain: "RemoteDesktopCapture", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Screen Recording permission not authorized."
            ])
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == (config.selectedDisplayID ?? CGMainDisplayID()) }) ?? content.displays.first else {
            throw NSError(domain: "RemoteDesktopCapture", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "No active display found for ScreenCaptureKit."
            ])
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = config.targetWidth
        streamConfig.height = config.targetHeight
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.frameRate))
        streamConfig.queueDepth = 5
        streamConfig.showsCursor = true

        let newStream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInteractive))
        try await newStream.startCapture()

        lock.lock()
        self.stream = newStream
        self.isCapturing = true
        lock.unlock()
    }

    /// Stop capture stream.
    public func stopCapture() async throws {
        lock.lock()
        let activeStream = self.stream
        self.stream = nil
        self.isCapturing = false
        lock.unlock()

        if let activeStream = activeStream {
            try await activeStream.stopCapture()
        }
    }

    // MARK: - SCStreamOutput Delegate

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()

        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            if let tiffData = nsImage.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                delegate?.frameCaptureEngine(self, didCaptureFrame: jpegData, timestamp: timeStamp)
            }
        }
    }
}
