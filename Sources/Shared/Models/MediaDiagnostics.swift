import Foundation

/// Pipeline stage diagnostic result to pinpoint where screen frames stop.
public enum PipelineDiagnosticStage: String, Codable, Sendable {
    case healthy = "Pipeline Operating Normally"
    case capture = "Capture Issue (No frames captured from system)"
    case encoding = "Encoding Issue (Frames captured but failed to encode)"
    case transport = "Transport Issue (Frames sent but not received by remote peer)"
    case reception = "Reception Issue (Connection active but zero frames received)"
    case decoding = "Decoding Issue (Frames received but failed to decode)"
    case rendering = "Rendering Issue (Frames decoded but failed to render to screen)"
}

/// Real-time media health metrics across the screen capture, transport, and rendering pipeline.
public struct MediaHealthMetrics: Codable, Sendable, Equatable {
    public var framesCaptured: Int64 = 0
    public var framesEncoded: Int64 = 0
    public var framesSent: Int64 = 0
    public var framesReceived: Int64 = 0
    public var framesDecoded: Int64 = 0
    public var framesRendered: Int64 = 0
    public var lastFrameTimestamp: Double = 0.0
    public var currentFps: Double = 0.0
    public var bitrateMbps: Double = 0.0
    public var rttMs: Double = 0.0
    public var packetLossPercent: Double = 0.0
    public var activeResolution: String = "1920x1080"
    public var codec: String = "JPEG / Hardware Low-Latency"

    public init(
        framesCaptured: Int64 = 0,
        framesEncoded: Int64 = 0,
        framesSent: Int64 = 0,
        framesReceived: Int64 = 0,
        framesDecoded: Int64 = 0,
        framesRendered: Int64 = 0,
        lastFrameTimestamp: Double = 0.0,
        currentFps: Double = 0.0,
        bitrateMbps: Double = 0.0,
        rttMs: Double = 0.0,
        packetLossPercent: Double = 0.0,
        activeResolution: String = "1920x1080",
        codec: String = "JPEG / Hardware Low-Latency"
    ) {
        self.framesCaptured = framesCaptured
        self.framesEncoded = framesEncoded
        self.framesSent = framesSent
        self.framesReceived = framesReceived
        self.framesDecoded = framesDecoded
        self.framesRendered = framesRendered
        self.lastFrameTimestamp = lastFrameTimestamp
        self.currentFps = currentFps
        self.bitrateMbps = bitrateMbps
        self.rttMs = rttMs
        self.packetLossPercent = packetLossPercent
        self.activeResolution = activeResolution
        self.codec = codec
    }

    /// Evaluates the media pipeline and returns the stage responsible for any stall or failure.
    public func diagnosePipeline(isHost: Bool) -> PipelineDiagnosticStage {
        if isHost {
            if framesCaptured == 0 {
                return .capture
            }
            if framesEncoded == 0 {
                return .encoding
            }
            if framesSent == 0 {
                return .transport
            }
            return .healthy
        } else {
            // Controller / Viewer perspective
            if framesReceived == 0 {
                return .reception
            }
            if framesDecoded == 0 {
                return .decoding
            }
            if framesRendered == 0 {
                return .rendering
            }
            return .healthy
        }
    }
}
