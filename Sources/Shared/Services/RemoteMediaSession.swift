import Foundation
import CoreGraphics

/// Delegate protocol for remote media session frame rendering and health telemetry.
public protocol RemoteMediaSessionDelegate: AnyObject {
    func mediaSession(_ session: RemoteMediaSession, didReceiveDecodedImage image: CGImage, timestamp: Double)
    func mediaSession(_ session: RemoteMediaSession, didReceiveDecodedFrame frameData: Data, timestamp: Double)
    func mediaSession(_ session: RemoteMediaSession, didUpdateHealth metrics: MediaHealthMetrics)
    func mediaSessionDidStall(_ session: RemoteMediaSession, stage: PipelineDiagnosticStage)
}

public extension RemoteMediaSessionDelegate {
    func mediaSession(_ session: RemoteMediaSession, didReceiveDecodedFrame frameData: Data, timestamp: Double) {}
}

/// Explicit media session abstraction managing real-time video streaming, hardware decoding, health telemetry, and frame pacing.
public final class RemoteMediaSession: @unchecked Sendable {
    public enum SessionRole: String, Codable, Sendable {
        case host          // Streams screen to remote viewer
        case controller    // Receives and renders remote screen
    }

    public static let shared = RemoteMediaSession()

    public weak var delegate: RemoteMediaSessionDelegate?

    private(set) public var role: SessionRole?
    private(set) public var isRunning: Bool = false
    private(set) public var isPaused: Bool = false

    private var metrics = MediaHealthMetrics()
    private let lock = NSLock()

    // Bounded startup queue for early captured frames before media channel is fully open (Requirement 14)
    private var earlyFrameQueue: [(Data, Double)] = []
    private let maxEarlyQueueCapacity = 2

    // Hardware decoder for controller
    private let videoDecoder = VideoHardwareDecoder()

    // FPS calculation tracking
    private var frameCountInInterval: Int = 0
    private var lastFpsCalculationTime: Date = Date()
    private var lastFrameReceivedDate: Date?
    private var watchdogTimer: Timer?

    private var transportSender: (@Sendable (Data, Double) async throws -> Void)?

    private init() {
        videoDecoder.onDecodedFrame = { [weak self] cgImage, timestamp in
            guard let self = self else { return }
            self.lock.lock()
            self.metrics.framesDecoded += 1
            let currentMetrics = self.metrics
            self.lock.unlock()

            self.delegate?.mediaSession(self, didReceiveDecodedImage: cgImage, timestamp: timestamp)
            self.delegate?.mediaSession(self, didUpdateHealth: currentMetrics)
        }
    }

    /// Start a media session in a specific role (host or controller).
    public func start(role: SessionRole, transportSender: (@Sendable (Data, Double) async throws -> Void)? = nil) {
        lock.lock()
        self.role = role
        self.isRunning = true
        self.isPaused = false
        self.transportSender = transportSender
        self.metrics = MediaHealthMetrics()
        self.metrics.codec = "H.264 / VideoToolbox Hardware"
        self.frameCountInInterval = 0
        self.lastFpsCalculationTime = Date()
        self.lastFrameReceivedDate = nil

        let pendingFrames = self.earlyFrameQueue
        self.earlyFrameQueue.removeAll()
        lock.unlock()

        print("[RemoteMediaSession] Started media session with role: \(role.rawValue)")

        // Drain any bounded early queued frames if sender is available
        if let sender = transportSender, !pendingFrames.isEmpty {
            Task {
                for (frame, ts) in pendingFrames {
                    try? await sender(frame, ts)
                }
            }
        }

        if role == .controller {
            startWatchdog()
        }
    }

    /// Stop and clean up active media session.
    public func stop() {
        stopWatchdog()

        lock.lock()
        self.isRunning = false
        self.isPaused = false
        self.transportSender = nil
        self.role = nil
        self.earlyFrameQueue.removeAll()
        videoDecoder.invalidate()
        lock.unlock()

        print("[RemoteMediaSession] Stopped media session")
    }

    /// Pause video streaming.
    public func pause() {
        lock.lock()
        self.isPaused = true
        lock.unlock()
    }

    /// Resume video streaming.
    public func resume() {
        lock.lock()
        self.isPaused = false
        lock.unlock()
    }

    // MARK: - Frame Delivery & Telemetry

    /// Host records capture of raw screen buffer.
    public func recordCapturedFrame() {
        lock.lock()
        metrics.framesCaptured += 1
        lock.unlock()
    }

    private func prepareFrameForSending() -> ((Data, Double) async throws -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning && !isPaused else { return nil }
        metrics.framesEncoded += 1
        return transportSender
    }

    private func recordSentFrame(timestamp: Double) {
        lock.lock()
        defer { lock.unlock() }
        metrics.framesSent += 1
        metrics.lastFrameTimestamp = timestamp
    }

    private func queueEarlyFrame(_ frameData: Data, timestamp: Double) {
        lock.lock()
        defer { lock.unlock() }
        if isRunning && !isPaused {
            if earlyFrameQueue.count >= maxEarlyQueueCapacity {
                earlyFrameQueue.removeFirst() // Drop oldest frame (Requirement 14)
            }
            earlyFrameQueue.append((frameData, timestamp))
        }
    }

    /// Host sends video frame over transport, safely queuing up to 2 frames if transport is in startup.
    public func sendVideoFrame(_ frameData: Data, timestamp: Double) async throws {
        let sender = prepareFrameForSending()
        if let sender = sender {
            try await sender(frameData, timestamp)
            recordSentFrame(timestamp: timestamp)
        } else {
            queueEarlyFrame(frameData, timestamp: timestamp)
        }
    }

    /// Controller receives raw video frame from transport.
    public func receiveVideoFrame(_ frameData: Data, timestamp: Double) {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }

        metrics.framesReceived += 1
        metrics.lastFrameTimestamp = timestamp
        lastFrameReceivedDate = Date()
        frameCountInInterval += 1

        let now = Date()
        let elapsed = now.timeIntervalSince(lastFpsCalculationTime)
        if elapsed >= 1.0 {
            metrics.currentFps = Double(frameCountInInterval) / elapsed
            frameCountInInterval = 0
            lastFpsCalculationTime = now

            // Approximate bitrate in Mbps based on frame size
            let bits = Double(frameData.count) * 8.0 * metrics.currentFps
            metrics.bitrateMbps = (bits / 1_000_000.0 * 10.0).rounded() / 10.0
        }

        let updatedMetrics = metrics
        lock.unlock()

        delegate?.mediaSession(self, didReceiveDecodedFrame: frameData, timestamp: timestamp)
        delegate?.mediaSession(self, didUpdateHealth: updatedMetrics)

        // Pass to hardware decoder
        if let packet = VideoFramePacket.deserialize(from: frameData) {
            videoDecoder.decode(packet: packet)
        }
    }

    /// Controller records that a decoded frame was successfully drawn to display.
    public func recordRenderedFrame() {
        lock.lock()
        metrics.framesRendered += 1
        lock.unlock()
    }

    /// Update network round-trip time metric.
    public func updateRTT(_ rttMs: Double) {
        lock.lock()
        metrics.rttMs = rttMs
        lock.unlock()
    }

    /// Retrieve snapshot of current media pipeline health metrics.
    public func getHealthMetrics() -> MediaHealthMetrics {
        lock.lock()
        defer { lock.unlock() }
        return metrics
    }

    /// Get diagnostic evaluation of media pipeline.
    public func diagnosePipeline() -> PipelineDiagnosticStage {
        lock.lock()
        defer { lock.unlock() }
        let isHost = role == .host
        return metrics.diagnosePipeline(isHost: isHost)
    }

    // MARK: - Stall Watchdog

    private func startWatchdog() {
        DispatchQueue.main.async { [weak self] in
            self?.watchdogTimer?.invalidate()
            self?.watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let (running, receivedCount, lastDate) = self.lock.withLock {
                    (self.isRunning, self.metrics.framesReceived, self.lastFrameReceivedDate)
                }

                guard running else { return }

                if receivedCount == 0 {
                    let stage = self.diagnosePipeline()
                    self.delegate?.mediaSessionDidStall(self, stage: stage)
                } else if let last = lastDate, Date().timeIntervalSince(last) > 5.0 {
                    let stage = self.diagnosePipeline()
                    self.delegate?.mediaSessionDidStall(self, stage: stage)
                }
            }
        }
    }

    private func stopWatchdog() {
        DispatchQueue.main.async { [weak self] in
            self?.watchdogTimer?.invalidate()
            self?.watchdogTimer = nil
        }
    }
}
