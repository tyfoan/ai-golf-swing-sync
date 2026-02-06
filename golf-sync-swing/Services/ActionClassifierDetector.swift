//
//  ActionClassifierDetector.swift
//  golf-sync-swing
//
//  Pose-based swing detector using 4-class Create ML Action Classifier.
//  Angle-independent: works from any camera position (front, side, behind).
//
//  Classes: backswing, downswing, follow_through, no_swing
//
//  Impact detection strategy:
//    Instead of a rigid state machine (backswing→downswing→follow_through),
//    we track the PROBABILITY CURVES over time and find the
//    downswing→follow_through transition — that's the impact point.
//
//  Pipeline per frame:
//    1. VNDetectHumanBodyPoseRequest → 18 body keypoints
//    2. Buffer keypoints in sliding window (60 frames)
//    3. Every N frames: run Action Classifier → get 4-class probabilities
//    4. Store prediction in history ring buffer
//    5. Analyze history for downswing→follow_through transition = impact
//

import CoreML
import AVFoundation
import Vision

final class ActionClassifierDetector: @unchecked Sendable {

    // MARK: - Configuration

    /// Prediction window size (must match model training: 60 frames = 2s at 30fps)
    private let predictionWindow: Int = 60

    /// Classification stride when idle (person visible but no swing activity)
    private let idleStride: Int = 15  // ~2/sec at 30fps

    /// Classification stride during active swing tracking (faster to catch transitions)
    private let activeStride: Int = 8  // ~3.75/sec

    /// Current adaptive stride
    private var classificationStride: Int = 15

    /// Minimum downswing probability to consider a prediction "has downswing"
    private let downswingThreshold: Double = 0.25

    /// Minimum follow_through probability for transition detection
    private let followThroughThreshold: Double = 0.35

    /// Minimum combined swing confidence (downswing + follow_through) for valid detection
    private let minSwingConfidence: Double = 0.50

    /// Minimum interval between swing detections
    private let minDetectionInterval: TimeInterval = 3.0

    /// Buffer before swing start for clip extraction
    private let preSwingBuffer: TimeInterval = 1.5

    /// Buffer after swing end for clip extraction
    private let postSwingBuffer: TimeInterval = 1.5

    // MARK: - Phase Labels (must match model training classes)

    private let backswingLabel = "backswing"
    private let downswingLabel = "downswing"
    private let followThroughLabel = "follow_through"
    private let noSwingLabel = "no_swing"

    // MARK: - ML Model

    private var model: MLModel?
    private var modelLoaded = false

    // MARK: - Pose Buffer

    private struct PoseFrame {
        let timestamp: TimeInterval
        let keypointsArray: MLMultiArray  // Shape: (3, 18)
    }

    private var poseBuffer: [PoseFrame] = []
    private var frameCounter: Int = 0
    private var totalFramesProcessed: Int = 0

    // MARK: - Prediction History (for transition detection)

    private struct PredictionRecord {
        let timestamp: TimeInterval      // Timestamp of LAST frame in the window
        let windowStart: TimeInterval    // Timestamp of FIRST frame in the window
        let label: String
        let probabilities: [String: Double]
    }

    private var predictionHistory: [PredictionRecord] = []
    private let maxHistorySize: Int = 30  // ~10 seconds of predictions

    // MARK: - Detection State

    private let lock = NSLock()
    private var lastDetectionTime: TimeInterval = -10.0

    /// Track consecutive no-pose frames for idle detection
    private var consecutiveNoPoseFrames: Int = 0
    private let noPoseIdleThreshold: Int = 30

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
        print("ActionClassifierDetector: Loading 4-class model...")

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all

            // Try v2 first (better model: 89% accuracy, 86% downswing precision)
            if let url = Bundle.main.url(forResource: "GolfSwingClassifier_v2", withExtension: "mlmodelc") {
                model = try MLModel(contentsOf: url, configuration: config)
                modelLoaded = true
                print("  Loaded GolfSwingClassifier_v2")
                logModelInfo()
                return
            }

            // Fall back to v1
            if let url = Bundle.main.url(forResource: "GolfSwingClassifier", withExtension: "mlmodelc") {
                model = try MLModel(contentsOf: url, configuration: config)
                modelLoaded = true
                print("  Loaded GolfSwingClassifier")
                logModelInfo()
                return
            }

            print("  No Action Classifier model in bundle")
            print("  Add GolfSwingClassifier_v2.mlmodel to the Xcode target")
            modelLoaded = false
        } catch {
            print("  FAILED: \(error.localizedDescription)")
            modelLoaded = false
        }
    }

    private func logModelInfo() {
        guard let model else { return }
        let desc = model.modelDescription
        for (name, feature) in desc.inputDescriptionsByName {
            print("  Input: \(name) shape=\(feature.multiArrayConstraint?.shape ?? [])")
        }
        for (name, _) in desc.outputDescriptionsByName {
            print("  Output: \(name)")
        }
    }

    // MARK: - Public API

    func processFrame(_ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) {
        totalFramesProcessed += 1

        guard let poseArray = detectPose(from: pixelBuffer) else {
            consecutiveNoPoseFrames += 1
            if consecutiveNoPoseFrames > noPoseIdleThreshold {
                isMotionDetected = false
                classificationStride = idleStride
            }
            return
        }

        consecutiveNoPoseFrames = 0
        isMotionDetected = true

        lock.lock()

        poseBuffer.append(PoseFrame(timestamp: timestamp, keypointsArray: poseArray))

        // Keep buffer at window size
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
        predictionHistory.removeAll()
        frameCounter = 0
        totalFramesProcessed = 0
        lastDetectionTime = -10.0
        isTrackingSwing = false
        isMotionDetected = false
        consecutiveNoPoseFrames = 0
        classificationStride = idleStride
        print("ActionClassifierDetector: Reset")
    }

    // MARK: - Pose Detection

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

        do {
            return try observation.keypointsMultiArray()
        } catch {
            return nil
        }
    }

    // MARK: - Classification

    private func runClassification(frames: [PoseFrame]) {
        guard modelLoaded, let model else { return }

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

    private func buildPredictionInput(from frames: [PoseFrame]) -> MLMultiArray? {
        guard frames.count == predictionWindow else { return nil }

        let firstShape = frames[0].keypointsArray.shape
        guard firstShape.count == 2 else { return nil }

        let numComponents = firstShape[0].intValue  // 3
        let numJoints = firstShape[1].intValue       // 18

        do {
            let result = try MLMultiArray(
                shape: [predictionWindow as NSNumber,
                        numComponents as NSNumber,
                        numJoints as NSNumber],
                dataType: .float32
            )

            let resultPtr = UnsafeMutablePointer<Float>(OpaquePointer(result.dataPointer))
            let frameStride = numComponents * numJoints

            for (frameIdx, frame) in frames.enumerated() {
                let src = frame.keypointsArray
                let dstOffset = frameIdx * frameStride

                if src.dataType == .double {
                    let doubleSrc = UnsafeMutablePointer<Double>(OpaquePointer(src.dataPointer))
                    for i in 0..<frameStride {
                        resultPtr[dstOffset + i] = Float(doubleSrc[i])
                    }
                } else {
                    let floatSrc = UnsafeMutablePointer<Float>(OpaquePointer(src.dataPointer))
                    for i in 0..<frameStride {
                        resultPtr[dstOffset + i] = floatSrc[i]
                    }
                }
            }

            return result
        } catch {
            return nil
        }
    }

    // MARK: - Prediction Processing + Impact Detection

    private func processPrediction(_ prediction: MLFeatureProvider, frames: [PoseFrame]) {
        guard let labelValue = prediction.featureValue(for: "label") else { return }

        let label = labelValue.stringValue

        let probabilities: [String: Double]
        if let probsValue = prediction.featureValue(for: "labelProbabilities"),
           let probs = probsValue.dictionaryValue as? [String: Double] {
            probabilities = probs
        } else {
            probabilities = [label: 1.0]
        }

        let windowEnd = frames.last?.timestamp ?? 0
        let windowStart = frames.first?.timestamp ?? 0

        // Store prediction
        let record = PredictionRecord(
            timestamp: windowEnd,
            windowStart: windowStart,
            label: label,
            probabilities: probabilities
        )

        lock.lock()
        predictionHistory.append(record)
        if predictionHistory.count > maxHistorySize {
            predictionHistory.removeFirst()
        }
        lock.unlock()

        // Update tracking state + adaptive stride
        let isSwingPhase = (label == backswingLabel || label == downswingLabel || label == followThroughLabel)
        isTrackingSwing = isSwingPhase
        classificationStride = isSwingPhase ? activeStride : idleStride

        // Report phase for UI
        let confidence = probabilities[label] ?? 0
        onPhaseChanged?(label, confidence)

        // Log periodically
        if totalFramesProcessed % 90 == 0 {
            let pDown = probabilities[downswingLabel] ?? 0
            let pFollow = probabilities[followThroughLabel] ?? 0
            let pBack = probabilities[backswingLabel] ?? 0
            print("ActionClassifier: \(label) (\(Int(confidence * 100))%)  back=\(Int(pBack * 100)) down=\(Int(pDown * 100)) follow=\(Int(pFollow * 100))")
        }

        // Check for impact transition
        checkForImpact()
    }

    /// Analyze prediction history for downswing→follow_through transition.
    ///
    /// Impact = the moment the club hits the ball = transition from downswing to follow_through.
    ///
    /// We look for a prediction that recently had high downswing probability,
    /// followed by a prediction with high follow_through probability.
    /// The impact timestamp is estimated from the probability crossover.
    private func checkForImpact() {
        lock.lock()
        let history = Array(predictionHistory.suffix(8))
        let currentTime = history.last?.timestamp ?? 0

        guard currentTime - lastDetectionTime > minDetectionInterval else {
            lock.unlock()
            return
        }
        lock.unlock()

        guard history.count >= 2 else { return }

        // Scan for the pattern: ...downswing-heavy... → ...follow_through-heavy...
        // Find the last prediction with significant downswing, followed by follow_through
        var lastDownswingRecord: PredictionRecord?
        var firstFollowThroughRecord: PredictionRecord?

        for record in history {
            let pDown = record.probabilities[downswingLabel] ?? 0
            let pFollow = record.probabilities[followThroughLabel] ?? 0

            if pDown >= downswingThreshold {
                // This prediction has significant downswing — track it
                lastDownswingRecord = record
                firstFollowThroughRecord = nil  // Reset: need follow_through AFTER this
            } else if pFollow >= followThroughThreshold && lastDownswingRecord != nil {
                // Follow_through after downswing — transition found
                if firstFollowThroughRecord == nil {
                    firstFollowThroughRecord = record
                }
            }
        }

        // Also detect backswing→follow_through (downswing too brief to catch explicitly)
        if lastDownswingRecord == nil {
            var lastBackswingRecord: PredictionRecord?
            for record in history {
                let pBack = record.probabilities[backswingLabel] ?? 0
                let pFollow = record.probabilities[followThroughLabel] ?? 0

                if pBack >= 0.4 {
                    lastBackswingRecord = record
                    firstFollowThroughRecord = nil
                } else if pFollow >= followThroughThreshold && lastBackswingRecord != nil {
                    if firstFollowThroughRecord == nil {
                        lastDownswingRecord = lastBackswingRecord  // Use backswing as proxy
                        firstFollowThroughRecord = record
                    }
                }
            }
        }

        guard let downswingPred = lastDownswingRecord,
              let followPred = firstFollowThroughRecord else {
            return
        }

        // Validate: combined confidence should be meaningful
        let peakDownswing = downswingPred.probabilities[downswingLabel] ?? 0
        let peakFollow = followPred.probabilities[followThroughLabel] ?? 0
        guard (peakDownswing + peakFollow) >= minSwingConfidence else { return }

        // Estimate impact timestamp from the transition
        let impactTime = estimateImpactTime(downswingPred: downswingPred, followPred: followPred)

        // Find swing start: look for earliest backswing in history
        let swingStartTime = findSwingStart(in: history, before: downswingPred.timestamp)

        let swing = SwingBounds(
            startTime: max(0, swingStartTime - preSwingBuffer),
            impactTime: impactTime,
            endTime: followPred.timestamp + postSwingBuffer,
            confidence: Double(peakDownswing + peakFollow) / 2.0,
            detectionTime: followPred.timestamp,
            audioConfirmed: false
        )

        lock.lock()
        lastDetectionTime = followPred.timestamp
        // Clear history to prevent re-detecting the same swing
        predictionHistory.removeAll()
        lock.unlock()

        print("ActionClassifier IMPACT: \(String(format: "%.2f", swing.startTime))s -> impact=\(String(format: "%.2f", swing.impactTime))s -> \(String(format: "%.2f", swing.endTime))s  (down=\(Int(peakDownswing * 100))% follow=\(Int(peakFollow * 100))%)")
        onSwingDetected?(swing)
    }

    /// Estimate the impact timestamp from the downswing→follow_through transition.
    ///
    /// Uses probability crossover: the point where P(downswing) and P(follow_through)
    /// are roughly equal is approximately the impact frame.
    ///
    /// Each prediction covers a 2-second window ending at `timestamp`.
    /// The model's label reflects the dominant action in that window.
    /// Impact is near the end of the window when downswing is labeled
    /// (since the actual downswing is very short ~150ms).
    private func estimateImpactTime(downswingPred: PredictionRecord, followPred: PredictionRecord) -> TimeInterval {
        let windowDuration = Double(predictionWindow) / 30.0  // 2.0 seconds

        // Check if the follow_through prediction itself contains residual downswing probability
        // — this means the transition happened WITHIN that window
        let pDown = followPred.probabilities[downswingLabel] ?? 0
        let pFollow = followPred.probabilities[followThroughLabel] ?? 0

        if pDown > 0.1 && pFollow > 0.1 {
            // Transition is within this window. Use probability ratio to estimate position.
            // Higher P(downswing) → impact is closer to the END of the window
            // Higher P(follow_through) → impact is closer to the START of the window
            let fraction = pDown / (pDown + pFollow)
            // Impact is fraction of the way from window start to window end
            // But offset: downswing is at the START of the transition window
            return followPred.windowStart + windowDuration * (1.0 - fraction)
        }

        // Sharp transition between predictions — impact is near the boundary
        // Downswing is very short (~150ms), so impact is near the END of the downswing window
        return downswingPred.timestamp - 0.3
    }

    /// Find the earliest backswing timestamp in history before a given time.
    private func findSwingStart(in history: [PredictionRecord], before cutoff: TimeInterval) -> TimeInterval {
        var earliest = cutoff
        for record in history {
            guard record.timestamp <= cutoff else { continue }
            let pBack = record.probabilities[backswingLabel] ?? 0
            if pBack >= 0.3 && record.windowStart < earliest {
                earliest = record.windowStart
            }
        }
        return earliest
    }
}
