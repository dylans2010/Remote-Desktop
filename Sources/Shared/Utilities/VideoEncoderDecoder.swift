import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo
import CoreGraphics
import CoreImage

/// Video codec format used for remote screen streaming.
public enum VideoCodecType: UInt8, Codable, Sendable {
    case h264 = 0x01
    case jpeg = 0x02
}

/// Adaptive streaming quality profile.
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

/// Structured binary video frame packet transmitted across network transport.
public struct VideoFramePacket: Sendable {
    public static let magicHeader: UInt32 = 0x56494446 // 'VIDF'

    public let sequenceNumber: UInt64
    public let timestamp: Double
    public let codec: VideoCodecType
    public let isKeyframe: Bool
    public let width: UInt16
    public let height: UInt16
    public let sps: Data?
    public let pps: Data?
    public let payload: Data

    public init(
        sequenceNumber: UInt64,
        timestamp: Double,
        codec: VideoCodecType,
        isKeyframe: Bool,
        width: UInt16,
        height: UInt16,
        sps: Data? = nil,
        pps: Data? = nil,
        payload: Data
    ) {
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.codec = codec
        self.isKeyframe = isKeyframe
        self.width = width
        self.height = height
        self.sps = sps
        self.pps = pps
        self.payload = payload
    }

    /// Serialize into binary format with zero JSON overhead.
    public func serialize() -> Data {
        let spsData = sps ?? Data()
        let ppsData = pps ?? Data()

        var data = Data(capacity: 28 + spsData.count + ppsData.count + payload.count)

        var magic = VideoFramePacket.magicHeader.bigEndian
        data.append(Data(bytes: &magic, count: 4))

        data.append(codec.rawValue)
        data.append(isKeyframe ? 1 : 0)

        var w = width.bigEndian
        data.append(Data(bytes: &w, count: 2))

        var h = height.bigEndian
        data.append(Data(bytes: &h, count: 2))

        var seq = sequenceNumber.bigEndian
        data.append(Data(bytes: &seq, count: 8))

        var tsBits = timestamp.bitPattern.bigEndian
        data.append(Data(bytes: &tsBits, count: 8))

        var spsLen = UInt16(spsData.count).bigEndian
        data.append(Data(bytes: &spsLen, count: 2))

        var ppsLen = UInt16(ppsData.count).bigEndian
        data.append(Data(bytes: &ppsLen, count: 2))

        if !spsData.isEmpty {
            data.append(spsData)
        }
        if !ppsData.isEmpty {
            data.append(ppsData)
        }
        data.append(payload)

        return data
    }

    /// Deserialize from binary stream.
    public static func deserialize(from data: Data) -> VideoFramePacket? {
        guard data.count >= 28 else { return nil }

        let magic = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard magic == VideoFramePacket.magicHeader else {
            // Check if fallback raw JPEG payload
            return VideoFramePacket(
                sequenceNumber: 0,
                timestamp: Date().timeIntervalSince1970,
                codec: .jpeg,
                isKeyframe: true,
                width: 1920,
                height: 1080,
                payload: data
            )
        }

        let codecRaw = data[4]
        guard let codec = VideoCodecType(rawValue: codecRaw) else { return nil }
        let isKeyframe = data[5] != 0

        let width = data.subdata(in: 6..<8).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let height = data.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let seq = data.subdata(in: 10..<18).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        let tsBits = data.subdata(in: 18..<26).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        let timestamp = Double(bitPattern: tsBits)

        let spsLen = Int(data.subdata(in: 26..<28).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
        guard data.count >= 30 else { return nil }
        let ppsLen = Int(data.subdata(in: 28..<30).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })

        var offset = 30
        var spsData: Data? = nil
        if spsLen > 0 {
            guard data.count >= offset + spsLen else { return nil }
            spsData = data.subdata(in: offset..<offset + spsLen)
            offset += spsLen
        }

        var ppsData: Data? = nil
        if ppsLen > 0 {
            guard data.count >= offset + ppsLen else { return nil }
            ppsData = data.subdata(in: offset..<offset + ppsLen)
            offset += ppsLen
        }

        let payload = data.subdata(in: offset..<data.count)

        return VideoFramePacket(
            sequenceNumber: seq,
            timestamp: timestamp,
            codec: codec,
            isKeyframe: isKeyframe,
            width: width,
            height: height,
            sps: spsData,
            pps: ppsData,
            payload: payload
        )
    }
}

// MARK: - Hardware Compression Output Callback

private func compressionCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard status == noErr, let sampleBuffer = sampleBuffer, CMSampleBufferIsValid(sampleBuffer) else { return }
    guard let refCon = outputCallbackRefCon else { return }
    let encoder = Unmanaged<VideoHardwareEncoder>.fromOpaque(refCon).takeUnretainedValue()
    encoder.handleCompressedSampleBuffer(sampleBuffer, infoFlags: infoFlags)
}

// MARK: - VideoHardwareEncoder

/// Hardware-accelerated VideoToolbox H.264/HEVC encoder with fallback support.
public final class VideoHardwareEncoder: @unchecked Sendable {
    private var compressionSession: VTCompressionSession?
    private var sequenceNumber: UInt64 = 0
    private var currentWidth: Int32 = 0
    private var currentHeight: Int32 = 0
    private let lock = NSLock()

    // Fallback CoreImage context for software compression if VT unavailable
    private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
    private lazy var srgbColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    public var onEncodedPacket: ((VideoFramePacket) -> Void)?

    public init() {}

    /// Setup or reconfigure VTCompressionSession for display dimensions.
    public func setup(width: Int32, height: Int32, profile: SessionQualityProfile = .automatic) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if let session = compressionSession, currentWidth == width && currentHeight == height {
            return true
        }

        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }

        currentWidth = width
        currentHeight = height
        sequenceNumber = 0

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        var newSession: VTCompressionSession?

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
            compressionSessionOut: &newSession
        )

        guard status == noErr, let session = newSession else {
            print("[VideoEncoder] VTCompressionSessionCreate failed with status \(status). Fallback enabled.")
            return false
        }

        // Configure low-latency real-time properties
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: profile.targetBitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: profile.targetFrameRate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: profile.targetFrameRate as CFNumber) // IDR keyframe every 1s
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)

        VTCompressionSessionPrepareToEncodeFrames(session)
        self.compressionSession = session

        print("[VideoEncoder] Initialized hardware H.264 compression: \(width)x\(height) @ \(profile.targetFrameRate)fps, \(profile.targetBitrate / 1000) kbps")
        return true
    }

    /// Encode CVPixelBuffer pixel frame.
    public func encode(pixelBuffer: CVPixelBuffer, timestamp: Double) {
        lock.lock()
        let session = compressionSession
        let width = currentWidth
        let height = currentHeight
        let seq = sequenceNumber
        sequenceNumber += 1
        lock.unlock()

        if let session = session {
            let pts = CMTime(seconds: timestamp, preferredTimescale: 600)
            let duration = CMTime(value: 1, timescale: 60)
            var flagsOut: VTEncodeInfoFlags = []

            let status = VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: pixelBuffer,
                presentationTimeStamp: pts,
                duration: duration,
                frameProperties: nil,
                sourceFrameRefcon: nil,
                infoFlagsOut: &flagsOut
            )

            if status != noErr {
                print("[VideoEncoder] VTCompressionSessionEncodeFrame error: \(status)")
            }
        } else {
            // Hardware compression not ready: encode via lossy JPEG fallback
            autoreleasepool {
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let options: [CIImageRepresentationOption: Any] = [
                    CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.65
                ]
                if let jpegData = ciContext.jpegRepresentation(of: ciImage, colorSpace: srgbColorSpace, options: options) {
                    let packet = VideoFramePacket(
                        sequenceNumber: seq,
                        timestamp: timestamp,
                        codec: .jpeg,
                        isKeyframe: true,
                        width: UInt16(max(1, width)),
                        height: UInt16(max(1, height)),
                        payload: jpegData
                    )
                    onEncodedPacket?(packet)
                }
            }
        }
    }

    fileprivate func handleCompressedSampleBuffer(_ sampleBuffer: CMSampleBuffer, infoFlags: VTEncodeInfoFlags) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard status == noErr, let ptr = dataPointer, length > 0 else { return }

        let payloadData = Data(bytes: ptr, count: length)
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // Determine if IDR / keyframe
        var isKeyframe = false
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
           let first = attachments.first {
            let notSync = (first[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false
            isKeyframe = !notSync
        }

        var spsData: Data? = nil
        var ppsData: Data? = nil

        if isKeyframe, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            var spsPointer: UnsafePointer<UInt8>?
            var spsSize: Int = 0
            var ppsPointer: UnsafePointer<UInt8>?
            var ppsSize: Int = 0
            var paramCount: Int = 0

            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDesc,
                parameterSetIndex: 0,
                parameterSetPointerOut: &spsPointer,
                parameterSetSizeOut: &spsSize,
                parameterSetCountOut: &paramCount,
                nalUnitHeaderLengthOut: nil
            )
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDesc,
                parameterSetIndex: 1,
                parameterSetPointerOut: &ppsPointer,
                parameterSetSizeOut: &ppsSize,
                parameterSetCountOut: &paramCount,
                nalUnitHeaderLengthOut: nil
            )

            if let spsPtr = spsPointer, spsSize > 0 {
                spsData = Data(bytes: spsPtr, count: spsSize)
            }
            if let ppsPtr = ppsPointer, ppsSize > 0 {
                ppsData = Data(bytes: ppsPtr, count: ppsSize)
            }
        }

        lock.lock()
        let seq = sequenceNumber
        let w = currentWidth
        let h = currentHeight
        lock.unlock()

        let packet = VideoFramePacket(
            sequenceNumber: seq,
            timestamp: pts,
            codec: .h264,
            isKeyframe: isKeyframe,
            width: UInt16(max(1, w)),
            height: UInt16(max(1, h)),
            sps: spsData,
            pps: ppsData,
            payload: payloadData
        )

        onEncodedPacket?(packet)
    }

    public func invalidate() {
        lock.lock()
        defer { lock.unlock() }

        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
    }
}

// MARK: - VideoHardwareDecoder

/// Hardware-accelerated VideoToolbox H.264 decoder rendering to CGImage.
public final class VideoHardwareDecoder: @unchecked Sendable {
    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private let lock = NSLock()

    public var onDecodedFrame: ((CGImage, Double) -> Void)?

    public init() {}

    /// Decode incoming packet and emit decoded CGImage.
    public func decode(packet: VideoFramePacket) {
        if packet.codec == .jpeg {
            decodeJpeg(packet.payload, timestamp: packet.timestamp)
            return
        }

        lock.lock()
        // If keyframe with new SPS/PPS parameters, recreate format description and decompression session
        if packet.isKeyframe, let sps = packet.sps, let pps = packet.pps {
            sps.withUnsafeBytes { spsRaw in
                pps.withUnsafeBytes { ppsRaw in
                    guard let spsPtr = spsRaw.bindMemory(to: UInt8.self).baseAddress,
                          let ppsPtr = ppsRaw.bindMemory(to: UInt8.self).baseAddress else { return }

                    let pointers: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
                    let sizes: [Int] = [sps.count, pps.count]
                    var newFormatDesc: CMVideoFormatDescription?

                    let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 2,
                        parameterSetPointers: pointers,
                        parameterSetSizes: sizes,
                        nalUnitHeaderLength: 4,
                        formatDescriptionOut: &newFormatDesc
                    )

                    if status == noErr, let formatDesc = newFormatDesc {
                        self.formatDescription = formatDesc
                        self.setupDecompressionSession(formatDescription: formatDesc)
                    }
                }
            }
        }

        guard let session = decompressionSession, let formatDesc = formatDescription else {
            lock.unlock()
            return
        }
        lock.unlock()

        // Create CMBlockBuffer with packet NAL unit payload
        var blockBuffer: CMBlockBuffer?
        let memStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: packet.payload.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: packet.payload.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard memStatus == noErr, let bb = blockBuffer else { return }
        packet.payload.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = CMBlockBufferReplaceDataBytes(with: base, blockBuffer: bb, offsetIntoDestination: 0, dataLength: packet.payload.count)
        }

        // Create CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = packet.payload.count
        var timing = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: CMTime(seconds: packet.timestamp, preferredTimescale: 600),
            decodeTimeStamp: CMTime.invalid
        )

        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let sb = sampleBuffer else { return }

        var flagsOut: VTDecodeInfoFlags = []
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sb,
            flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: &flagsOut
        ) { [weak self] status, infoFlags, imageBuffer, pts, duration in
            guard status == noErr, let imageBuffer = imageBuffer else { return }
            self?.handleDecompressedImageBuffer(imageBuffer, timestamp: packet.timestamp)
        }

        if decodeStatus != noErr {
            print("[VideoDecoder] VTDecompressionSessionDecodeFrame error: \(decodeStatus)")
        }
    }

    private func setupDecompressionSession(formatDescription: CMVideoFormatDescription) {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }

        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: nil,
            decompressionSessionOut: &decompressionSession
        )

        if status == noErr {
            print("[VideoDecoder] Initialized hardware H.264 decompression session successfully.")
        } else {
            print("[VideoDecoder] Failed to initialize VTDecompressionSession: \(status)")
        }
    }

    fileprivate func handleDecompressedImageBuffer(_ imageBuffer: CVImageBuffer, timestamp: Double) {
        var cgImage: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(imageBuffer, options: nil, imageOut: &cgImage)
        if status == noErr, let image = cgImage {
            onDecodedFrame?(image, timestamp)
        }
    }

    private func decodeJpeg(_ data: Data, timestamp: Double) {
        guard let dataProvider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(jpegDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            return
        }
        onDecodedFrame?(cgImage, timestamp)
    }

    public func invalidate() {
        lock.lock()
        defer { lock.unlock() }

        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        formatDescription = nil
    }
}
