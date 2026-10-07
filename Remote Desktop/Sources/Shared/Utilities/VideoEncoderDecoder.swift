import Foundation
import VideoToolbox
import CoreMedia

/// Session streaming adaptive quality profile.
public enum SessionQualityProfile: String, Codable, Sendable {
    case automatic
    case high
    case balanced
    case lowLatency

    public var targetBitrate: Int32 {
        switch self {
        case .high: return 8_000_000        // 8 Mbps
        case .balanced: return 4_000_000    // 4 Mbps
        case .lowLatency: return 2_000_000  // 2 Mbps
        case .automatic: return 4_000_000   // adaptive default
        }
    }

    public var targetFrameRate: Int32 {
        switch self {
        case .high: return 60
        case .balanced: return 30
        case .lowLatency: return 60
        case .automatic: return 60
        }
    }
}

private func compressionCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard status == noErr, let sampleBuffer = sampleBuffer, CMSampleBufferIsValid(sampleBuffer) else { return }
    let encoder = Unmanaged<VideoEncoderDecoder>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()

    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    var length = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

    if let dataPointer = dataPointer {
        let frameData = Data(bytes: dataPointer, count: length)
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let keyframe = !infoFlags.contains(.frameDropped)
        encoder.onEncodedFrameReady?(frameData, pts, keyframe)
    }
}

/// Hardware-accelerated VideoToolbox encoder/decoder wrapper for low-latency H.264/HEVC.
public final class VideoEncoderDecoder: @unchecked Sendable {
    private var compressionSession: VTCompressionSession?
    private var decompressionSession: VTDecompressionSession?
    private let lock = NSLock()

    public var onEncodedFrameReady: ((Data, Double, Bool) -> Void)?

    public init() {}

    /// Initialize VTCompressionSession for H.264 encoding.
    public func setupEncoder(width: Int32, height: Int32, profile: SessionQualityProfile = .automatic) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionCallback,
            refcon: selfPointer,
            compressionSessionOut: &compressionSession
        )

        guard status == noErr, let session = compressionSession else {
            print("[VideoEncoder] Failed to create VTCompressionSession: \(status)")
            return false
        }

        // Configure low-latency real-time properties
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: profile.targetBitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: profile.targetFrameRate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (profile.targetFrameRate * 2) as CFNumber)

        VTCompressionSessionPrepareToEncodeFrames(session)
        print("[VideoEncoder] Low latency VideoToolbox H.264 encoder initialized (\(width)x\(height), \(profile.targetBitrate / 1000) kbps)")
        return true
    }

    /// Encode CVImageBuffer pixel frame into compressed video stream payload.
    public func encode(imageBuffer: CVImageBuffer, timestamp: Double) {
        lock.lock()
        guard let session = compressionSession else {
            lock.unlock()
            return
        }
        lock.unlock()

        let presentationTimeStamp = CMTime(seconds: timestamp, preferredTimescale: 600)
        let duration = CMTime(value: 1, timescale: 60)

        var flags: VTEncodeInfoFlags = []
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )

        if status != noErr {
            print("[VideoEncoder] VTCompressionSessionEncodeFrame error: \(status)")
        }
    }

    /// Teardown compression/decompression sessions.
    public func invalidate() {
        lock.lock()
        defer { lock.unlock() }

        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        if let decSession = decompressionSession {
            VTDecompressionSessionInvalidate(decSession)
            decompressionSession = nil
        }
    }
}
