import Foundation
import CoreGraphics
import ScreenCaptureKit
import CoreImage
import ImageIO

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
    func frameCaptureEngineDidFail(_ engine: ScreenCaptureEngine, error: Error)
}

/// High-performance ScreenCaptureKit capture engine for macOS with GPU-accelerated frame compression and pacing.
public final class ScreenCaptureEngine: NSObject, SCStreamOutput, @unchecked Sendable {
    public weak var delegate: FrameCaptureDelegate?

    private var stream: SCStream?
    private(set) public var isCapturing: Bool = false
    private let lock = NSLock()

    // Hardware H.264 video encoder
    private let videoEncoder = VideoHardwareEncoder()

    public override init() {
        super.init()
        videoEncoder.onEncodedPacket = { [weak self] packet in
            guard let self = self else { return }
            let serialized = packet.serialize()
            self.delegate?.frameCaptureEngine(self, didCaptureFrame: serialized, timestamp: packet.timestamp)
        }
    }

    /// Retrieve list of active system displays via ScreenCaptureKit.
    public static func availableDisplays() async throws -> [DisplayInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays.map { display in
            DisplayInfo(
                id: display.displayID,
                name: "Display \(display.displayID)",
                width: display.width,
                height: display.height,
                isMain: display.displayID == CGMainDisplayID()
            )
        }
    }

    /// Start capturing display stream using ScreenCaptureKit.
    public func startCapture(config: FrameCaptureConfig = FrameCaptureConfig()) async throws {
        guard ScreenRecordingPermissionManager.shared.isAuthorized else {
            let error = NSError(domain: "RemoteDesktopCapture", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Screen Recording permission not authorized."
            ])
            delegate?.frameCaptureEngineDidFail(self, error: error)
            throw error
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == (config.selectedDisplayID ?? CGMainDisplayID()) }) ?? content.displays.first else {
            let error = NSError(domain: "RemoteDesktopCapture", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "No active display found for ScreenCaptureKit."
            ])
            delegate?.frameCaptureEngineDidFail(self, error: error)
            throw error
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = min(config.targetWidth, display.width)
        streamConfig.height = min(config.targetHeight, display.height)
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.frameRate))
        streamConfig.queueDepth = 3
        streamConfig.showsCursor = true
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA

        _ = videoEncoder.setup(width: Int32(streamConfig.width), height: Int32(streamConfig.height))

        let newStream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInteractive))
        try await newStream.startCapture()

        setStreamActive(newStream)

        print("[ScreenCaptureEngine] ScreenCaptureKit streaming active at \(streamConfig.width)x\(streamConfig.height) @ \(config.frameRate)fps")
    }

    private func setStreamActive(_ stream: SCStream) {
        lock.lock()
        defer { lock.unlock() }
        self.stream = stream
        self.isCapturing = true
    }

    private func clearStream() -> SCStream? {
        lock.lock()
        defer { lock.unlock() }
        let activeStream = self.stream
        self.stream = nil
        self.isCapturing = false
        videoEncoder.invalidate()
        return activeStream
    }

    /// Stop capture stream cleanly.
    public func stopCapture() async throws {
        let activeStream = clearStream()
        if let activeStream = activeStream {
            try await activeStream.stopCapture()
            print("[ScreenCaptureEngine] ScreenCaptureKit stream stopped")
        }
    }

    // MARK: - SCStreamOutput Delegate

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Track frame captured in media health telemetry
        RemoteMediaSession.shared.recordCapturedFrame()

        let timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        videoEncoder.encode(pixelBuffer: imageBuffer, timestamp: timeStamp)
    }
}
