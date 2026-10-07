import Foundation
import ReplayKit
import UIKit

/// State of iOS ReplayKit screen broadcast stream.
public enum BroadcastState: String, Codable, Sendable {
    case stopped
    case starting
    case broadcasting
    case paused
    case error
}

/// Manages iOS/iPadOS screen broadcasting capabilities using ReplayKit within Apple's supported platform APIs.
public final class iOSBroadcastManager: NSObject, @unchecked Sendable {
    public static let shared = iOSBroadcastManager()

    private(set) public var broadcastState: BroadcastState = .stopped
    public var onFrameCaptured: ((Data, Double) -> Void)?

    private let lock = NSLock()

    private override init() {
        super.init()
    }

    /// Request start of in-app screen recording broadcast on iOS/iPadOS.
    public func startBroadcast() {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            print("[iOSBroadcastManager] RPScreenRecorder is not available on this device")
            return
        }

        lock.lock()
        broadcastState = .starting
        lock.unlock()

        recorder.startCapture(handler: { [weak self] sampleBuffer, sampleType, error in
            guard let self = self else { return }

            if let error = error {
                print("[iOSBroadcastManager] Capture error: \(error)")
                self.lock.lock()
                self.broadcastState = .error
                self.lock.unlock()
                return
            }

            guard sampleType == .video, CMSampleBufferIsValid(sampleBuffer) else { return }
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            let context = CIContext()

            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let uiImage = UIImage(cgImage: cgImage)
                if let jpegData = uiImage.jpegData(compressionQuality: 0.6) {
                    self.onFrameCaptured?(jpegData, timeStamp)
                }
            }
        }, completionHandler: { [weak self] error in
            guard let self = self else { return }
            self.lock.lock()
            if let error = error {
                print("[iOSBroadcastManager] Start capture completion error: \(error)")
                self.broadcastState = .error
            } else {
                self.broadcastState = .broadcasting
                print("[iOSBroadcastManager] In-app screen broadcast started successfully")
            }
            self.lock.unlock()
        })
    }

    /// Stop active broadcast session.
    public func stopBroadcast() {
        let recorder = RPScreenRecorder.shared()
        recorder.stopCapture { [weak self] error in
            guard let self = self else { return }
            self.lock.lock()
            self.broadcastState = .stopped
            self.lock.unlock()
            print("[iOSBroadcastManager] Screen broadcast stopped")
        }
    }
}
