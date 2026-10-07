import ReplayKit

/// Sample handler for the Remote Desktop iOS Broadcast Upload Extension.
class SampleHandler: RPBroadcastSampleHandler {
    private var frameCount: Int64 = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        // User started the broadcast extension
        print("[BroadcastExtension] Broadcast started successfully")
    }

    override func broadcastPaused() {
        // User paused the broadcast
        print("[BroadcastExtension] Broadcast paused")
    }

    override func broadcastResumed() {
        // User resumed the broadcast
        print("[BroadcastExtension] Broadcast resumed")
    }

    override func broadcastFinished() {
        // User finished the broadcast
        print("[BroadcastExtension] Broadcast finished")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        switch sampleBufferType {
        case .video:
            frameCount += 1
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

            // Memory-efficient CIImage / CGImage video frame processing
            autoreleasepool {
                let ciImage = CIImage(cvImageBuffer: imageBuffer)
                let context = CIContext(options: [.useSoftwareRenderer: false])
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    let uiImage = UIImage(cgImage: cgImage)
                    if let jpegData = uiImage.jpegData(compressionQuality: 0.5) {
                        // Deliver frame to shared transport or extension IPC mechanism
                        _ = jpegData
                        _ = timeStamp
                    }
                }
            }

        case .audioApp:
            // Process app audio sample buffer if required
            break

        case .audioMic:
            // Process microphone sample buffer if required
            break

        @unknown default:
            break
        }
    }
}
