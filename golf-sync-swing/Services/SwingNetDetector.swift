//
//  SwingNetDetector.swift
//  golf-sync-swing
//
//  SwingNet-based swing detection using the GolfDB pretrained model
//  Detects 9 swing events including precise Impact frame (event index 5)
//

import CoreML
import AVFoundation
import CoreImage
import Vision

/// SwingNet event indices
enum SwingNetEvent: Int, CaseIterable {
    case address = 0
    case toeUp = 1
    case midBackswing = 2
    case top = 3
    case midDownswing = 4
    case impact = 5          // Key event for sync!
    case midFollowThrough = 6
    case finish = 7
    case noEvent = 8

    var name: String {
        switch self {
        case .address: return "address"
        case .toeUp: return "toe_up"
        case .midBackswing: return "mid_backswing"
        case .top: return "top"
        case .midDownswing: return "mid_downswing"
        case .impact: return "impact"
        case .midFollowThrough: return "mid_follow_through"
        case .finish: return "finish"
        case .noEvent: return "no_event"
        }
    }

    var isSwingPhase: Bool {
        self != .noEvent
    }
}

/// SwingNet-based swing detector using the GolfDB pretrained model
/// Input: 64 frames × 3 channels × 160 × 160
/// Output: 64 frames × 9 event probabilities
final class SwingNetDetector: @unchecked Sendable {

    // MARK: - Configuration

    /// Number of frames for SwingNet input (fixed by model)
    private let windowSize: Int = 64

    /// Frame dimensions (fixed by model)
    private let frameWidth: Int = 160
    private let frameHeight: Int = 160

    /// Minimum confidence for impact detection (30% — person-crop boosts to ~35%;
    /// set below peak to handle graceful fallback when pose detection misses)
    private let impactConfidenceThreshold: Float = 0.30

    /// Minimum confidence for corroborating events (address or top-of-backswing)
    private let corroboratingEventThreshold: Float = 0.15

    /// Minimum frames where noEvent must be the dominant class (out of 64)
    private let minNoEventDominantFrames: Int = 24

    /// Events that must appear in temporal order for a valid swing
    private let requiredTemporalEvents: [SwingNetEvent] = [.address, .top, .impact]

    /// Minimum interval between swing detections
    private let minDetectionInterval: TimeInterval = 2.0

    /// Buffer before swing start for clip extraction
    private let preSwingBuffer: TimeInterval = 0.5

    /// Buffer after impact for clip extraction
    private let postImpactBuffer: TimeInterval = 1.0

    /// Adaptive classification stride based on motion state
    private var classificationInterval: Int { adaptiveStride }
    private var adaptiveStride: Int = 30  // Start conservative (idle)

    // MARK: - ML Model

    private var swingNet: SwingNet?
    private var modelLoaded = false

    // MARK: - Frame Buffer (store processed data, not raw buffers)

    private struct FrameData {
        let timestamp: TimeInterval
        let rgbData: ContiguousArray<UInt8>  // Raw 0-255 RGB data (3 * 160 * 160)
    }

    private var frameBuffer: ContiguousArray<FrameData> = []
    private var frameCounter: Int = 0

    // MARK: - CIContext for image processing

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Motion Gate (replaces Vision-based person detection)

    private let motionGate = MotionGateService()

    // MARK: - Pose-Based Person Detection (infrequent, for spatial cropping)

    private var cachedPersonBounds: CGRect?    // Normalized 0-1 coords (Vision bottom-left origin)
    private var poseDetectionCounter: Int = 0
    private let poseDetectionInterval: Int = 60  // ~2x/sec at 30fps

    // MARK: - ImageNet Normalization (CRITICAL for SwingNet!)
    // SwingNet was trained with ImageNet normalization, NOT simple 0-1 scaling
    private let imagenetMean: [Float] = [0.485, 0.456, 0.406]  // RGB order
    private let imagenetStd: [Float] = [0.229, 0.224, 0.225]   // RGB order

    // MARK: - State

    private let lock = NSLock()

    /// Current dominant event
    private var currentEvent: SwingNetEvent = .noEvent
    private var currentConfidence: Float = 0

    /// Swing tracking state
    private var lastDetectionTime: TimeInterval = -10.0
    private var swingStartTime: TimeInterval?
    private var impactTime: TimeInterval?

    /// Track if we're in an active swing sequence
    private var swingSequenceStarted: Bool = false
    private var lastSwingEventTime: TimeInterval = 0

    /// Public tracking state
    private(set) var isTrackingSwing: Bool = false

    /// All swings detected so far (for offline multi-swing scanning)
    private(set) var detectedSwings: [SwingBounds] = []

    /// Frame count for logging
    private var totalFramesProcessed: Int = 0

    // MARK: - Callbacks

    /// Called when a complete swing is detected
    var onSwingDetected: (@Sendable (SwingBounds) -> Void)?

    /// Called when event changes (for UI feedback)
    var onPhaseChanged: ((_ phase: String, _ confidence: Double) -> Void)?

    // MARK: - Init

    init() {
        loadModel()
    }

    private func loadModel() {
        print("🔧 SwingNetDetector: Attempting to load SwingNet model...")
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all  // Use Neural Engine when available
            swingNet = try SwingNet(configuration: config)
            modelLoaded = true
            print("✅ SwingNetDetector: SwingNet loaded (GolfDB pretrained)")
            print("   - impactConfidenceThreshold: \(impactConfidenceThreshold)")
            print("   - corroboratingEventThreshold: \(corroboratingEventThreshold)")
            print("   - minNoEventDominantFrames: \(minNoEventDominantFrames)")
            print("   - windowSize: \(windowSize) frames (~\(String(format: "%.1f", Double(windowSize) / 30.0))s at 30fps)")
            print("   - frameSize: \(frameWidth)x\(frameHeight)")
            print("   - normalization: ImageNet (mean=\(imagenetMean), std=\(imagenetStd))")
        } catch {
            modelLoaded = false
            print("❌ SwingNetDetector: FAILED to load model!")
            print("   - Error: \(error.localizedDescription)")
            print("   - Check that SwingNet.mlpackage is in the Xcode target")
        }
    }

    // MARK: - Public API

    /// Top-of-backswing timestamp from the last validated analysis (for sync enrichment)
    var topOfBackswingTime: TimeInterval? {
        guard let analysis = lastAnalysis,
              let topPeak = analysis.eventPeaks[.top],
              topPeak.prob >= corroboratingEventThreshold else { return nil }
        // We need frame timestamps — stored via lastAnalysisFrames
        guard let frames = lastAnalysisFrames,
              topPeak.frame < frames.count else { return nil }
        return frames[topPeak.frame].timestamp
    }

    /// Top-of-backswing confidence from the last validated analysis
    var topOfBackswingConfidence: Double {
        guard let analysis = lastAnalysis,
              let topPeak = analysis.eventPeaks[.top] else { return 0 }
        return Double(topPeak.prob)
    }

    /// Whether motion is currently detected (for UI feedback)
    private(set) var isMotionDetected: Bool = false

    /// Process a video frame for swing detection
    func processFrame(_ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) {
        totalFramesProcessed += 1

        // Extract RGB data from pixel buffer (outside lock for performance)
        guard let rgbData = extractRGBData(from: pixelBuffer) else {
            return
        }

        // Update motion gate and adaptive stride
        let motionState = motionGate.update(with: rgbData)
        isMotionDetected = motionState != .idle

        switch motionState {
        case .idle:  adaptiveStride = 30  // ~1/sec at 30fps
        case .active: adaptiveStride = 8  // ~3.75/sec
        case .peak:  adaptiveStride = 5   // ~6/sec
        }

        lock.lock()

        // Add frame to buffer
        frameBuffer.append(FrameData(timestamp: timestamp, rgbData: rgbData))

        // Keep buffer at window size
        while frameBuffer.count > windowSize {
            frameBuffer.removeFirst()
        }

        // Log once when buffer first fills
        if frameBuffer.count == windowSize && totalFramesProcessed == windowSize {
            print("📹 SwingNet: Buffer ready, analyzing...")
        }

        // Check refractory period
        guard timestamp - lastDetectionTime > minDetectionInterval else {
            lock.unlock()
            return
        }

        // Run classification periodically when we have enough frames
        frameCounter += 1
        if frameCounter >= classificationInterval && frameBuffer.count >= windowSize {
            frameCounter = 0
            lock.unlock()
            runSwingNetClassification()
            return
        }

        lock.unlock()
    }

    /// Reset detector state
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        frameBuffer.removeAll()
        frameCounter = 0
        currentEvent = .noEvent
        currentConfidence = 0
        lastDetectionTime = -10.0
        swingStartTime = nil
        impactTime = nil
        isTrackingSwing = false
        swingSequenceStarted = false
        lastSwingEventTime = 0
        detectedSwings.removeAll()
        totalFramesProcessed = 0
        isMotionDetected = false
        adaptiveStride = 30
        motionGate.reset()
        cachedPersonBounds = nil
        poseDetectionCounter = 0
        lastAnalysis = nil
        lastAnalysisFrames = nil
        print("🔄 SwingNetDetector: Reset")
    }

    // MARK: - Image Processing

    private func extractRGBData(from pixelBuffer: CVPixelBuffer) -> ContiguousArray<UInt8>? {
        // Run pose detection every N frames to update person crop region
        poseDetectionCounter += 1
        if poseDetectionCounter >= poseDetectionInterval {
            poseDetectionCounter = 0
            detectPersonPose(from: pixelBuffer)
        }

        // Autoreleasepool drains CIImage intermediates each frame (prevents memory accumulation)
        return autoreleasepool {
            var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            // Crop to person region if pose was detected
            if let bounds = cachedPersonBounds {
                let imgW = ciImage.extent.width
                let imgH = ciImage.extent.height
                // Vision coords: bottom-left origin, normalized 0-1
                let cropRect = CGRect(
                    x: bounds.origin.x * imgW,
                    y: bounds.origin.y * imgH,
                    width: bounds.width * imgW,
                    height: bounds.height * imgH
                ).integral
                ciImage = ciImage.cropped(to: cropRect)
                    .transformed(by: CGAffineTransform(
                        translationX: -cropRect.origin.x,
                        y: -cropRect.origin.y
                    ))
            }

            // Scale (cropped or full) frame to 160x160
            let currentWidth = ciImage.extent.width
            let currentHeight = ciImage.extent.height
            let scaleX = CGFloat(frameWidth) / currentWidth
            let scaleY = CGFloat(frameHeight) / currentHeight
            let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            // Fresh plain buffer each frame (no IOSurface — avoids GPU buffer pool exhaustion)
            var outputBuffer: CVPixelBuffer?
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                frameWidth,
                frameHeight,
                kCVPixelFormatType_32BGRA,
                nil,
                &outputBuffer
            )

            guard let output = outputBuffer else { return nil }

            ciContext.render(scaled, to: output)

            // Extract raw UInt8 RGB data (normalization deferred to buildMLInput)
            CVPixelBufferLockBaseAddress(output, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(output, .readOnly) }

            guard let baseAddress = CVPixelBufferGetBaseAddress(output) else { return nil }

            let bytesPerRow = CVPixelBufferGetBytesPerRow(output)
            let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

            let pixelCount = frameWidth * frameHeight
            var rgbData = ContiguousArray<UInt8>()
            rgbData.reserveCapacity(3 * pixelCount)

            // Extract in CHW order (channels first): R, G, B planes
            // Store raw UInt8 values — ImageNet normalization happens in buildMLInput()

            // R plane
            for y in 0..<frameHeight {
                for x in 0..<frameWidth {
                    let offset = y * bytesPerRow + x * 4
                    rgbData.append(buffer[offset + 2])  // R (BGRA format, R is at offset+2)
                }
            }
            // G plane
            for y in 0..<frameHeight {
                for x in 0..<frameWidth {
                    let offset = y * bytesPerRow + x * 4
                    rgbData.append(buffer[offset + 1])  // G
                }
            }
            // B plane
            for y in 0..<frameHeight {
                for x in 0..<frameWidth {
                    let offset = y * bytesPerRow + x * 4
                    rgbData.append(buffer[offset])       // B
                }
            }

            return rgbData
        }
    }

    // MARK: - Pose-Based Person Detection

    private func detectPersonPose(from pixelBuffer: CVPixelBuffer) {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            cachedPersonBounds = nil
            return
        }

        guard let observation = request.results?.first else {
            cachedPersonBounds = nil
            return
        }

        // Collect all recognized keypoints with sufficient confidence
        let allPoints = observation.availableJointNames.compactMap { jointName -> CGPoint? in
            guard let point = try? observation.recognizedPoint(jointName),
                  point.confidence > 0.1 else { return nil }
            return point.location  // Normalized 0-1, Vision bottom-left origin
        }

        guard allPoints.count >= 3 else {
            cachedPersonBounds = nil
            return
        }

        // Compute bounding box from keypoints
        let xs = allPoints.map(\.x)
        let ys = allPoints.map(\.y)
        let minX = xs.min()!
        let maxX = xs.max()!
        let minY = ys.min()!
        let maxY = ys.max()!

        // Expand 30% for club arc
        let width = maxX - minX
        let height = maxY - minY
        let expandX = width * 0.3
        let expandY = height * 0.3

        cachedPersonBounds = CGRect(
            x: max(0, minX - expandX),
            y: max(0, minY - expandY),
            width: min(1.0 - max(0, minX - expandX), width + 2 * expandX),
            height: min(1.0 - max(0, minY - expandY), height + 2 * expandY)
        )
    }

    // MARK: - ML Classification

    private func runSwingNetClassification() {
        guard modelLoaded, let model = swingNet else {
            print("⚠️ SwingNet: Model not loaded")
            return
        }

        lock.lock()
        guard frameBuffer.count >= windowSize else {
            lock.unlock()
            return
        }

        // Copy frame data while locked
        let frames = Array(frameBuffer.suffix(windowSize))
        lock.unlock()

        // Build input
        guard let input = buildMLInput(from: frames) else {
            print("⚠️ SwingNet: Failed to build input")
            return
        }

        do {
            let prediction = try model.prediction(video_frames: input)
            processSwingNetOutput(prediction.event_probabilities, frames: frames)
        } catch {
            print("❌ SwingNet prediction failed: \(error.localizedDescription)")
        }
    }

    private func buildMLInput(from frames: [FrameData]) -> MLMultiArray? {
        do {
            // Model expects: (1, 64, 3, 160, 160) - batch, frames, channels, height, width
            let input = try MLMultiArray(shape: [1, 64, 3, 160, 160] as [NSNumber], dataType: .float32)

            let pixelsPerChannel = frameWidth * frameHeight  // 25600
            let pixelsPerFrame = 3 * pixelsPerChannel        // 76800

            // Pre-compute normalization constants: (pixel/255.0 - mean) / std = pixel * scale + bias
            let scales: [Float] = [
                1.0 / (255.0 * imagenetStd[0]),
                1.0 / (255.0 * imagenetStd[1]),
                1.0 / (255.0 * imagenetStd[2])
            ]
            let biases: [Float] = [
                -imagenetMean[0] / imagenetStd[0],
                -imagenetMean[1] / imagenetStd[1],
                -imagenetMean[2] / imagenetStd[2]
            ]

            // Use pointer for fast copying
            let ptr = UnsafeMutablePointer<Float>(OpaquePointer(input.dataPointer))

            for (frameIdx, frameData) in frames.enumerated() {
                let frameOffset = frameIdx * pixelsPerFrame

                // Normalize UInt8 → Float with ImageNet stats during copy
                // CHW layout: R plane, G plane, B plane (each pixelsPerChannel)
                for ch in 0..<3 {
                    let channelOffset = frameOffset + ch * pixelsPerChannel
                    let srcOffset = ch * pixelsPerChannel
                    let scale = scales[ch]
                    let bias = biases[ch]
                    for i in 0..<pixelsPerChannel {
                        ptr[channelOffset + i] = Float(frameData.rgbData[srcOffset + i]) * scale + bias
                    }
                }
            }

            return input
        } catch {
            print("❌ Failed to build SwingNet input: \(error)")
            return nil
        }
    }

    // MARK: - Output Analysis

    /// Parsed SwingNet output — single pass extracts everything needed for validation
    private struct SwingNetAnalysis {
        /// Per-event: (peakFrameIndex, peakProbability)
        var eventPeaks: [SwingNetEvent: (frame: Int, prob: Float)] = [:]

        /// Number of frames where noEvent is the dominant class
        var noEventDominantFrameCount: Int = 0

        /// Impact-specific convenience
        var impactFrame: Int { eventPeaks[.impact]?.frame ?? 0 }
        var impactProb: Float { eventPeaks[.impact]?.prob ?? 0 }

        func impactTimestamp(in frames: [FrameData]) -> TimeInterval {
            frames[impactFrame].timestamp
        }
    }

    /// Last successful analysis (for top-of-backswing extraction by VideoSyncEngine)
    private var lastAnalysis: SwingNetAnalysis?

    /// Frame timestamps from the last successful analysis
    private var lastAnalysisFrames: [FrameData]?

    /// Single O(64×9) pass through the output tensor
    private func analyzeFullOutput(_ probabilities: MLMultiArray) -> SwingNetAnalysis {
        var analysis = SwingNetAnalysis()
        let eventCount = 9 // 8 swing events + noEvent

        // Initialize peaks with zero probability
        for event in SwingNetEvent.allCases {
            analysis.eventPeaks[event] = (frame: 0, prob: 0)
        }

        for frameIdx in 0..<64 {
            var dominantEvent: Int = 0
            var dominantProb: Float = -1

            for eventIdx in 0..<eventCount {
                let prob = probabilities[[0, frameIdx, eventIdx] as [NSNumber]].floatValue

                // Track dominant class for this frame
                if prob > dominantProb {
                    dominantProb = prob
                    dominantEvent = eventIdx
                }

                // Track per-event peak
                guard let event = SwingNetEvent(rawValue: eventIdx) else { continue }
                if prob > (analysis.eventPeaks[event]?.prob ?? 0) {
                    analysis.eventPeaks[event] = (frame: frameIdx, prob: prob)
                }
            }

            // Count noEvent-dominant frames
            if dominantEvent == SwingNetEvent.noEvent.rawValue {
                analysis.noEventDominantFrameCount += 1
            }
        }

        return analysis
    }

    // MARK: - Validation Pipeline

    /// Returns nil if swing is valid, or a rejection reason string for logging
    private func validateSwingDetection(_ analysis: SwingNetAnalysis) -> String? {
        // 1. Impact confidence (person detection gate removed — using motion gate instead)
        if analysis.impactProb < impactConfidenceThreshold {
            return "impact confidence too low (\(Int(analysis.impactProb * 100))% < \(Int(impactConfidenceThreshold * 100))%)"
        }

        // 2. Impact frame position (edge artifact filter)
        if analysis.impactProb >= 0.30 {
            // Confident: accept frames 4-60
            guard analysis.impactFrame > 3 && analysis.impactFrame < 61 else {
                return "impact at edge frame \(analysis.impactFrame) (high conf)"
            }
        } else {
            // Lower confidence: require middle of window (frames 17-47)
            guard analysis.impactFrame > 16 && analysis.impactFrame < 48 else {
                return "impact at edge frame \(analysis.impactFrame) (low conf)"
            }
        }

        // 3. NoEvent dominance — real swings are mostly "nothing happening"
        if analysis.noEventDominantFrameCount < minNoEventDominantFrames {
            return "too few noEvent frames (\(analysis.noEventDominantFrameCount)/64, need \(minNoEventDominantFrames))"
        }

        // 4. Temporal event order: address < top < impact
        let addressFrame = analysis.eventPeaks[.address]?.frame ?? 0
        let topFrame = analysis.eventPeaks[.top]?.frame ?? 0
        let impactFrame = analysis.impactFrame

        if !(addressFrame < topFrame && topFrame < impactFrame) {
            return "temporal order violated: address=\(addressFrame) top=\(topFrame) impact=\(impactFrame)"
        }

        // 5. Multi-event corroboration: at least address OR top must have meaningful probability
        let addressProb = analysis.eventPeaks[.address]?.prob ?? 0
        let topProb = analysis.eventPeaks[.top]?.prob ?? 0

        if addressProb < corroboratingEventThreshold && topProb < corroboratingEventThreshold {
            return "no corroborating events (address=\(Int(addressProb * 100))%, top=\(Int(topProb * 100))%)"
        }

        return nil // All checks passed
    }

    // MARK: - Output Processing

    private func processSwingNetOutput(_ probabilities: MLMultiArray, frames: [FrameData]) {
        // Full analysis: single pass extracts all event peaks + noEvent stats
        let analysis = analyzeFullOutput(probabilities)

        // Run 6-layer validation pipeline
        if let rejection = validateSwingDetection(analysis) {
            print("⛳ SwingNet: rejected: \(rejection)")
            return
        }

        let impactTimestamp = analysis.impactTimestamp(in: frames)

        let addressTs = frames[analysis.eventPeaks[.address]?.frame ?? 0].timestamp
        let topTs = frames[analysis.eventPeaks[.top]?.frame ?? 0].timestamp
        let finishTs = frames[min(analysis.eventPeaks[.finish]?.frame ?? 63, frames.count - 1)].timestamp
        print("📊 SwingNet: VALIDATED impact=\(String(format: "%.2f", impactTimestamp))s (\(Int(analysis.impactProb * 100))%)")
        print("   events: address=\(String(format: "%.2f", addressTs))s top=\(String(format: "%.2f", topTs))s impact=\(String(format: "%.2f", impactTimestamp))s finish=\(String(format: "%.2f", finishTs))s")

        lock.lock()

        // Store analysis + frames for top-of-backswing extraction
        lastAnalysis = analysis
        lastAnalysisFrames = frames

        if impactTime == nil || abs(impactTimestamp - impactTime!) > minDetectionInterval {
            impactTime = impactTimestamp

            // Use actual detected event positions instead of fixed offsets
            let addressFrame = analysis.eventPeaks[.address]?.frame ?? 0
            let addressTimestamp = frames[addressFrame].timestamp

            // For end: use finish event if detected, otherwise fall back to fixed offset
            let finishFrame = analysis.eventPeaks[.finish]?.frame ?? min(63, analysis.impactFrame + 15)
            let finishTimestamp = frames[min(finishFrame, frames.count - 1)].timestamp

            // Add buffers: 0.5s before address, 0.5s after finish
            let swing = SwingBounds(
                startTime: max(0, addressTimestamp - preSwingBuffer),
                impactTime: impactTimestamp,
                endTime: finishTimestamp + postImpactBuffer,
                confidence: Double(analysis.impactProb),
                detectionTime: frames.last?.timestamp ?? impactTimestamp,
                audioConfirmed: false
            )

            detectedSwings.append(swing)
            lastDetectionTime = frames.last?.timestamp ?? impactTimestamp
            lock.unlock()

            print("🎯 SWING: \(String(format: "%.2f", swing.startTime))s → \(String(format: "%.2f", swing.impactTime))s → \(String(format: "%.2f", swing.endTime))s")
            onSwingDetected?(swing)
            onPhaseChanged?("impact", Double(analysis.impactProb))
        } else {
            lock.unlock()
        }
    }
}
