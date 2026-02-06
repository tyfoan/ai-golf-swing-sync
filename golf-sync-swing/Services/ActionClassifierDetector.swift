//
//  ActionClassifierDetector.swift
//  golf-sync-swing
//
//  Pose-based swing detector using Create ML Action Classifier.
//  Angle-independent: works from any camera position (front, side, behind).
//
//  Input:  CVPixelBuffer frames from camera
//  Output: SwingBounds when a swing is detected
//
//  Pipeline per frame:
//    1. VNDetectHumanBodyPoseRequest → 18 body keypoints (x, y, confidence)
//    2. Buffer keypoints in sliding window (predictionWindow frames)
//    3. Every classificationStride frames: run Action Classifier model
//    4. If "swing" confidence > threshold → fire onSwingDetected
//

import CoreML
import AVFoundation
import Vision

final class ActionClassifierDetector: @unchecked Sendable {

    // MARK: - Configuration

    /// Number of frames in the prediction window (must match model training)
    /// Create ML default for action classifiers is typically 60 frames
    private let predictionWindow: Int = 60

    /// How often to run classification (in frames). Lower = more responsive but more CPU.
    private let defaultClassificationStride: Int = 15

    /// Adaptive stride based on motion state
    private var classificationStride: Int = 15

    /// Minimum confidence for "swing" label to trigger detection
    private let swingConfidenceThreshold: Double = 0.7

    /// Minimum interval between swing detections (avoid duplicates)
    private let minDetectionInterval: TimeInterval = 3.0

    /// Buffer before detected swing for clip extraction
    private let preSwingBuffer: TimeInterval = 1.5

    /// Buffer after detected swing for clip extraction
    private let postSwingBuffer: TimeInterval = 1.5

    /// The label the model uses for swing class
    private let swingLabel = "swing"

    // MARK: - ML Model

    private var model: MLModel?
    private var modelLoaded = false

    // MARK: - Pose Buffer

    /// Single frame of pose data: (3, numJoints) MLMultiArray from Vision
    private struct PoseFrame {
        let timestamp: TimeInterval
        let keypointsArray: MLMultiArray  // Shape: (3, 18) — [x/y/conf, joint]
    }

    private var poseBuffer: [PoseFrame] = []
    private var frameCounter: Int = 0
    private var totalFramesProcessed: Int = 0

    // MARK: - Detection State

    private let lock = NSLock()
    private var lastDetectionTime: TimeInterval = -10.0
    private var firstSwingFrameTime: TimeInterval?

    // MARK: - Motion Gate

    /// Reuse lightweight motion gate for adaptive classification stride.
    /// Unlike SwingNet, we don't need pixel data for the model — only for motion gating.
    /// We track motion via pose presence/absence instead of pixel differencing.
    private var consecutiveNoPoseFrames: Int = 0
    private let noPoseIdleThreshold: Int = 30  // 1 second at 30fps → probably no person

    // MARK: - Public State

    private(set) var isTrackingSwing: Bool = false
    private(set) var isMotionDetected: Bool = false

    // MARK: - Callbacks

    var onSwingDetected: (@Sendable (SwingBounds) -> Void)?
    var onPhaseChanged: ((_ phase: String, _ confidence: Double) -> Void)?

    // MARK: - Init

    init() {
        loadModel()
    }

    private func loadModel() {
        print("ActionClassifierDetector: Loading model...")

        // Try loading the compiled model from the bundle
        // The model class name depends on how it's added to Xcode.
        // We try multiple approaches for flexibility.
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all

            // Approach 1: Try Xcode-generated class (if model is in project)
            if let modelURL = Bundle.main.url(
                forResource: "GolfSwingClassifier",
                withExtension: "mlmodelc"
            ) {
                model = try MLModel(contentsOf: modelURL, configuration: config)
                modelLoaded = true
                print("  Loaded GolfSwingClassifier from bundle")
                logModelInfo()
                return
            }

            // Approach 2: Try v2 model name
            if let modelURL = Bundle.main.url(
                forResource: "GolfSwingClassifier_v2",
                withExtension: "mlmodelc"
            ) {
                model = try MLModel(contentsOf: modelURL, configuration: config)
                modelLoaded = true
                print("  Loaded GolfSwingClassifier_v2 from bundle")
                logModelInfo()
                return
            }

            print("  No Action Classifier model found in bundle")
            print("  Add GolfSwingClassifier.mlmodel to the Xcode target")
            modelLoaded = false
        } catch {
            print("  FAILED to load model: \(error.localizedDescription)")
            modelLoaded = false
        }
    }

    private func logModelInfo() {
        guard let model else { return }
        let desc = model.modelDescription
        print("  Inputs:")
        for (name, feature) in desc.inputDescriptionsByName {
            print("    \(name): \(feature.type.rawValue), constraint: \(feature.multiArrayConstraint?.shape ?? [])")
        }
        print("  Outputs:")
        for (name, _) in desc.outputDescriptionsByName {
            print("    \(name)")
        }
        print("  predictionWindow: \(predictionWindow)")
        print("  swingConfidenceThreshold: \(swingConfidenceThreshold)")
    }

    // MARK: - Public API

    func processFrame(_ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) {
        totalFramesProcessed += 1

        // Run pose detection
        guard let poseArray = detectPose(from: pixelBuffer) else {
            // No person detected — update motion state
            consecutiveNoPoseFrames += 1
            if consecutiveNoPoseFrames > noPoseIdleThreshold {
                isMotionDetected = false
                classificationStride = 30  // Slow down when no person visible
            }
            return
        }

        // Person detected — reset idle counter
        consecutiveNoPoseFrames = 0
        isMotionDetected = true
        classificationStride = defaultClassificationStride

        lock.lock()

        // Add to pose buffer
        poseBuffer.append(PoseFrame(timestamp: timestamp, keypointsArray: poseArray))

        // Keep buffer at prediction window size
        while poseBuffer.count > predictionWindow {
            poseBuffer.removeFirst()
        }

        // Check refractory period
        guard timestamp - lastDetectionTime > minDetectionInterval else {
            lock.unlock()
            return
        }

        // Run classification periodically when buffer is full
        frameCounter += 1
        if frameCounter >= classificationStride && poseBuffer.count >= predictionWindow {
            frameCounter = 0
            let frames = Array(poseBuffer.suffix(predictionWindow))
            lock.unlock()
            runClassification(frames: frames)
            return
        }

        lock.unlock()
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        poseBuffer.removeAll()
        frameCounter = 0
        totalFramesProcessed = 0
        lastDetectionTime = -10.0
        firstSwingFrameTime = nil
        isTrackingSwing = false
        isMotionDetected = false
        consecutiveNoPoseFrames = 0
        classificationStride = defaultClassificationStride
        print("ActionClassifierDetector: Reset")
    }

    // MARK: - Pose Detection

    /// Extract body pose keypoints from a frame.
    /// Returns MLMultiArray of shape (3, 18) — [x/y/confidence, joint_index]
    private func detectPose(from pixelBuffer: CVPixelBuffer) -> MLMultiArray? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else {
            return nil
        }

        // keypointsMultiArray() returns (3, 18) — ready for Create ML Action Classifier
        do {
            return try observation.keypointsMultiArray()
        } catch {
            return nil
        }
    }

    // MARK: - Classification

    private func runClassification(frames: [PoseFrame]) {
        guard modelLoaded, let model else { return }

        // Build input: concatenate pose arrays along time axis
        // Each frame is (3, 18), we need (predictionWindow, 3, 18)
        guard let inputArray = buildPredictionInput(from: frames) else {
            return
        }

        do {
            let inputFeatures = try MLDictionaryFeatureProvider(
                dictionary: ["poses": MLFeatureValue(multiArray: inputArray)]
            )
            let prediction = try model.prediction(from: inputFeatures)

            processPrediction(prediction, frames: frames)
        } catch {
            if totalFramesProcessed % 300 == 0 {
                print("ActionClassifier: prediction failed: \(error.localizedDescription)")
            }
        }
    }

    /// Build MLMultiArray of shape (predictionWindow, 3, 18) from pose frames.
    private func buildPredictionInput(from frames: [PoseFrame]) -> MLMultiArray? {
        guard frames.count == predictionWindow else { return nil }

        // Determine joint count from first frame
        let firstShape = frames[0].keypointsArray.shape
        guard firstShape.count == 2 else { return nil }

        let numComponents = firstShape[0].intValue  // 3 (x, y, confidence)
        let numJoints = firstShape[1].intValue       // 18

        do {
            let result = try MLMultiArray(
                shape: [predictionWindow as NSNumber,
                        numComponents as NSNumber,
                        numJoints as NSNumber],
                dataType: .float32
            )

            let resultPtr = UnsafeMutablePointer<Float>(OpaquePointer(result.dataPointer))
            let frameStride = numComponents * numJoints  // 3 * 18 = 54

            for (frameIdx, frame) in frames.enumerated() {
                let src = frame.keypointsArray
                let srcPtr = UnsafeMutablePointer<Float>(OpaquePointer(src.dataPointer))

                // Copy entire (3, 18) frame into the right position
                let dstOffset = frameIdx * frameStride
                for i in 0..<frameStride {
                    // Handle potential type mismatch — keypointsMultiArray may be Double
                    if src.dataType == .double {
                        let doubleSrc = UnsafeMutablePointer<Double>(OpaquePointer(src.dataPointer))
                        resultPtr[dstOffset + i] = Float(doubleSrc[i])
                    } else {
                        resultPtr[dstOffset + i] = srcPtr[i]
                    }
                }
            }

            return result
        } catch {
            print("ActionClassifier: failed to build input: \(error)")
            return nil
        }
    }

    // MARK: - Prediction Processing

    private func processPrediction(_ prediction: MLFeatureProvider, frames: [PoseFrame]) {
        // Extract label and probabilities
        guard let labelValue = prediction.featureValue(for: "label") else {
            return
        }

        let label = labelValue.stringValue

        let probabilities: [String: Double]
        if let probsValue = prediction.featureValue(for: "labelProbabilities"),
           let probs = probsValue.dictionaryValue as? [String: Double] {
            probabilities = probs
        } else {
            probabilities = [label: 1.0]
        }

        let swingConfidence = probabilities[swingLabel] ?? 0.0

        // Log periodically
        if totalFramesProcessed % 90 == 0 {
            let topLabel = probabilities.max(by: { $0.value < $1.value })
            print("ActionClassifier: \(topLabel?.key ?? "?") (\(Int((topLabel?.value ?? 0) * 100))%)")
        }

        // Report phase for UI
        onPhaseChanged?(label, swingConfidence)

        // Check for swing detection
        guard swingConfidence >= swingConfidenceThreshold else {
            isTrackingSwing = false
            firstSwingFrameTime = nil
            return
        }

        // Swing detected!
        isTrackingSwing = true

        lock.lock()

        // Set first swing frame if not already tracking
        if firstSwingFrameTime == nil {
            firstSwingFrameTime = frames.first?.timestamp ?? 0
        }

        let detectionTimestamp = frames.last?.timestamp ?? 0

        // Check refractory period
        guard detectionTimestamp - lastDetectionTime > minDetectionInterval else {
            lock.unlock()
            return
        }

        lastDetectionTime = detectionTimestamp

        // Estimate swing bounds from the prediction window
        // The swing is somewhere within the window — use middle portion
        let windowStart = frames.first?.timestamp ?? 0
        let windowEnd = frames.last?.timestamp ?? 0
        let windowMid = (windowStart + windowEnd) / 2

        let swing = SwingBounds(
            startTime: max(0, windowStart - preSwingBuffer),
            impactTime: windowMid,  // Best estimate without phase-level detail
            endTime: windowEnd + postSwingBuffer,
            confidence: swingConfidence,
            detectionTime: detectionTimestamp,
            audioConfirmed: false
        )

        firstSwingFrameTime = nil
        lock.unlock()

        print("ActionClassifier SWING: \(String(format: "%.2f", swing.startTime))s -> \(String(format: "%.2f", swing.impactTime))s -> \(String(format: "%.2f", swing.endTime))s (\(Int(swingConfidence * 100))%)")
        onSwingDetected?(swing)
    }
}
