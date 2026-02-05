//
//  SwingNetDetector.swift
//  golf-sync-swing
//
//  SwingNet-based swing detection using the GolfDB pretrained model
//  Detects 9 swing events including precise Impact frame (event index 5)
//

import Vision
import CoreML
import AVFoundation
import CoreImage

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

    /// Minimum confidence for impact detection (20% to avoid false positives)
    private let impactConfidenceThreshold: Float = 0.20

    /// Minimum confidence for any swing event
    private let swingEventThreshold: Float = 0.20

    /// Minimum interval between swing detections
    private let minDetectionInterval: TimeInterval = 2.0

    /// Buffer before swing start for clip extraction
    private let preSwingBuffer: TimeInterval = 0.5

    /// Buffer after impact for clip extraction
    private let postImpactBuffer: TimeInterval = 1.0

    /// Process ML classification every N frames (higher = faster, lower = more responsive)
    private let classificationInterval: Int = 20  // ~1.5x per second at 30fps

    // MARK: - ML Model

    private var swingNet: SwingNet?
    private var modelLoaded = false

    // MARK: - Frame Buffer (store processed data, not raw buffers)

    private struct FrameData {
        let timestamp: TimeInterval
        let rgbData: [Float]  // Flattened RGB data (3 * 160 * 160)
    }

    private var frameBuffer: [FrameData] = []
    private var frameCounter: Int = 0

    // MARK: - CIContext for image processing

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Person Detection for Cropping

    /// Cached person bounding box (normalized 0-1 coordinates)
    private var cachedPersonBounds: CGRect?
    private var personDetectionCounter: Int = 0
    private let personDetectionInterval: Int = 30  // Detect every N frames (less frequent = faster)

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
            print("   - swingEventThreshold: \(swingEventThreshold)")
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

    /// Process a video frame for swing detection
    func processFrame(_ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) {
        totalFramesProcessed += 1

        // Extract RGB data from pixel buffer (outside lock for performance)
        guard let rgbData = extractRGBData(from: pixelBuffer) else {
            return
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
        totalFramesProcessed = 0
        cachedPersonBounds = nil
        personDetectionCounter = 0
        print("🔄 SwingNetDetector: Reset")
    }

    // MARK: - Image Processing

    private func extractRGBData(from pixelBuffer: CVPixelBuffer) -> [Float]? {
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // Detect person periodically and cache bounds
        personDetectionCounter += 1
        if personDetectionCounter >= personDetectionInterval || cachedPersonBounds == nil {
            personDetectionCounter = 0
            detectPerson(in: pixelBuffer)
        }

        // Crop to person if detected
        if let bounds = cachedPersonBounds {
            // Convert normalized bounds to pixel coordinates
            // Vision returns bounds with origin at bottom-left, CIImage uses bottom-left too
            let cropRect = CGRect(
                x: bounds.minX * imageWidth,
                y: bounds.minY * imageHeight,
                width: bounds.width * imageWidth,
                height: bounds.height * imageHeight
            )

            // Expand bounds by 20% to include club and ball
            let expansion: CGFloat = 0.2
            let expandedRect = cropRect.insetBy(
                dx: -cropRect.width * expansion,
                dy: -cropRect.height * expansion
            )

            // Clamp to image bounds
            let clampedRect = expandedRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

            if !clampedRect.isEmpty && clampedRect.width > 50 && clampedRect.height > 50 {
                ciImage = ciImage.cropped(to: clampedRect)
                // Reset origin after crop
                ciImage = ciImage.transformed(by: CGAffineTransform(translationX: -clampedRect.minX, y: -clampedRect.minY))
            }
        }

        // Scale to 160x160
        let currentWidth = ciImage.extent.width
        let currentHeight = ciImage.extent.height
        let scaleX = CGFloat(frameWidth) / currentWidth
        let scaleY = CGFloat(frameHeight) / currentHeight
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Create output buffer
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

        // Extract RGB data
        CVPixelBufferLockBaseAddress(output, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(output, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(output) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(output)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var rgbData: [Float] = []
        rgbData.reserveCapacity(3 * frameWidth * frameHeight)

        // Extract in CHW order (channels first): R, G, B planes
        // CRITICAL: Apply ImageNet normalization! SwingNet was trained with:
        //   normalized = (pixel/255.0 - mean) / std
        // Without this normalization, the model outputs garbage.

        // R plane
        for y in 0..<frameHeight {
            for x in 0..<frameWidth {
                let offset = y * bytesPerRow + x * 4
                let pixel = Float(buffer[offset + 2]) / 255.0  // R (BGRA format, R is at offset+2)
                let normalized = (pixel - imagenetMean[0]) / imagenetStd[0]
                rgbData.append(normalized)
            }
        }
        // G plane
        for y in 0..<frameHeight {
            for x in 0..<frameWidth {
                let offset = y * bytesPerRow + x * 4
                let pixel = Float(buffer[offset + 1]) / 255.0  // G
                let normalized = (pixel - imagenetMean[1]) / imagenetStd[1]
                rgbData.append(normalized)
            }
        }
        // B plane
        for y in 0..<frameHeight {
            for x in 0..<frameWidth {
                let offset = y * bytesPerRow + x * 4
                let pixel = Float(buffer[offset]) / 255.0      // B
                let normalized = (pixel - imagenetMean[2]) / imagenetStd[2]
                rgbData.append(normalized)
            }
        }

        return rgbData
    }

    // MARK: - Person Detection

    private func detectPerson(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectHumanRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("⚠️ Person detection error: \(error.localizedDescription)")
                return
            }

            guard let results = request.results as? [VNHumanObservation],
                  let person = results.first else {
                // No person detected, clear cache
                self.cachedPersonBounds = nil
                return
            }

            // Cache the detected bounds
            self.cachedPersonBounds = person.boundingBox
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
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

            // Use pointer for fast copying
            let ptr = UnsafeMutablePointer<Float>(OpaquePointer(input.dataPointer))

            for (frameIdx, frameData) in frames.enumerated() {
                let frameOffset = frameIdx * pixelsPerFrame

                // Copy all RGB data for this frame at once
                for i in 0..<pixelsPerFrame {
                    ptr[frameOffset + i] = frameData.rgbData[i]
                }
            }

            return input
        } catch {
            print("❌ Failed to build SwingNet input: \(error)")
            return nil
        }
    }

    // MARK: - Output Processing
    // Only detect impact event - use fixed offsets for start/end

    private func processSwingNetOutput(_ probabilities: MLMultiArray, frames: [FrameData]) {
        // Shape: (1, 64, 9) - find frame with max impact probability
        let impactEventIdx = SwingNetEvent.impact.rawValue

        var maxProb: Float = 0
        var maxFrameIdx: Int = 0

        for frameIdx in 0..<64 {
            let prob = probabilities[[0, frameIdx, impactEventIdx] as [NSNumber]].floatValue
            if prob > maxProb {
                maxProb = prob
                maxFrameIdx = frameIdx
            }
        }

        let impactTimestamp = frames[maxFrameIdx].timestamp

        // Validate: impact confidence must be meaningful (>=20%)
        guard maxProb >= impactConfidenceThreshold else { return }

        // Validate frame position based on confidence
        // Higher confidence = more lenient position requirements
        if maxProb >= 0.35 {
            // High confidence: accept anywhere except extreme edges
            guard maxFrameIdx > 3 && maxFrameIdx < 61 else { return }
        } else {
            // Lower confidence (20-35%): require middle of window
            guard maxFrameIdx > 20 && maxFrameIdx < 45 else { return }
        }

        print("📊 SwingNet: impact=\(String(format: "%.2f", impactTimestamp))s (\(Int(maxProb * 100))%)")

        lock.lock()
        if impactTime == nil || abs(impactTimestamp - impactTime!) > minDetectionInterval {
            impactTime = impactTimestamp

            // Use fixed offsets from impact
            let swing = SwingBounds(
                startTime: max(0, impactTimestamp - 1.5),
                impactTime: impactTimestamp,
                endTime: impactTimestamp + 1.5,
                confidence: Double(maxProb),
                detectionTime: frames.last?.timestamp ?? impactTimestamp,
                audioConfirmed: false
            )

            lastDetectionTime = frames.last?.timestamp ?? impactTimestamp
            lock.unlock()

            print("🎯 SWING: \(String(format: "%.2f", swing.startTime))s → \(String(format: "%.2f", swing.impactTime))s → \(String(format: "%.2f", swing.endTime))s")
            onSwingDetected?(swing)
            onPhaseChanged?("impact", Double(maxProb))
        } else {
            lock.unlock()
        }
    }
}
