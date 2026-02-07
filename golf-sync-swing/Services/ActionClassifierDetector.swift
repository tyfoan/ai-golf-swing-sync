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
    private let downswingThreshold: Double = 0.30

    /// Minimum follow_through probability for transition detection
    private let followThroughThreshold: Double = 0.30

    /// Minimum combined swing confidence (downswing + follow_through) for valid detection
    private let minSwingConfidence: Double = 0.40

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

            // Model preference order: v3 (fixed boundaries) > v2 > v1
            let modelNames = ["GolfSwingClassifier_v3", "GolfSwingClassifier_v2", "GolfSwingClassifier"]
            for name in modelNames {
                if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                    model = try MLModel(contentsOf: url, configuration: config)
                    modelLoaded = true
                    print("  Loaded \(name)")
                    logModelInfo()
                    return
                }
            }

            print("  No Action Classifier model in bundle")
            print("  Add GolfSwingClassifier_v3.mlmodel to the Xcode target")
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
        guard modelLoaded else {
            if totalFramesProcessed == 0 {
                print("ActionClassifier: skipping frames — model not loaded")
            }
            totalFramesProcessed += 1
            return
        }

        totalFramesProcessed += 1

        guard let poseArray = detectPose(from: pixelBuffer) else {
            consecutiveNoPoseFrames += 1
            if consecutiveNoPoseFrames == 1 || consecutiveNoPoseFrames % 60 == 0 {
                print("ActionClassifier: no pose detected (\(consecutiveNoPoseFrames) consecutive)")
            }
            if consecutiveNoPoseFrames > noPoseIdleThreshold {
                isMotionDetected = false
                classificationStride = idleStride
            }
            return
        }

        if consecutiveNoPoseFrames > 10 {
            print("ActionClassifier: pose recovered after \(consecutiveNoPoseFrames) frames")
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

        // Log buffer fill progress once
        if poseBuffer.count == predictionWindow && frameCounter == 0 && classificationCount == 0 {
            print("ActionClassifier: pose buffer full (\(predictionWindow) frames), starting classification")
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

    private var classificationCount: Int = 0
    private var classificationErrors: Int = 0

    private func runClassification(frames: [PoseFrame]) {
        guard modelLoaded, let model else { return }

        guard let inputArray = buildPredictionInput(from: frames) else {
            print("ActionClassifier: failed to build prediction input (frames=\(frames.count))")
            return
        }

        do {
            let inputFeatures = try MLDictionaryFeatureProvider(
                dictionary: ["poses": MLFeatureValue(multiArray: inputArray)]
            )
            let prediction = try model.prediction(from: inputFeatures)
            classificationCount += 1
            processPrediction(prediction, frames: frames)
        } catch {
            classificationErrors += 1
            if classificationErrors <= 3 || classificationErrors % 10 == 0 {
                print("ActionClassifier: prediction FAILED (\(classificationErrors)x): \(error.localizedDescription)")
            }
        }
    }

    private func buildPredictionInput(from frames: [PoseFrame]) -> MLMultiArray? {
        guard frames.count == predictionWindow else { return nil }

        // Vision's keypointsMultiArray() returns shape (1, 3, 18)
        // — 1 pose × 3 components (x, y, confidence) × 18 joints.
        // The model expects (60, 3, 18) — strip the leading 1 dimension.
        let firstShape = frames[0].keypointsArray.shape
        let numComponents: Int
        let numJoints: Int

        if firstShape.count == 3 {
            // Shape: (1, 3, 18) — typical Vision output
            numComponents = firstShape[1].intValue
            numJoints = firstShape[2].intValue
        } else if firstShape.count == 2 {
            // Shape: (3, 18)
            numComponents = firstShape[0].intValue
            numJoints = firstShape[1].intValue
        } else {
            print("ActionClassifier: unexpected pose shape \(firstShape)")
            return nil
        }

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

                // For (1, 3, 18) shape, data is contiguous — same layout as (3, 18)
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
            print("ActionClassifier: MLMultiArray creation failed: \(error)")
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

        // Report phase for UI
        let confidence = probabilities[label] ?? 0
        onPhaseChanged?(label, confidence)

        // Update tracking state + adaptive stride
        let isActiveSwing = (label == downswingLabel || label == followThroughLabel || label == backswingLabel)
        isTrackingSwing = isActiveSwing
        classificationStride = isActiveSwing ? activeStride : idleStride

        // Log every classification
        let pDown = probabilities[downswingLabel] ?? 0
        let pFollow = probabilities[followThroughLabel] ?? 0
        let pBack = probabilities[backswingLabel] ?? 0
        print("🧠 ActionClassifier[\(classificationCount)]: \(label) (\(Int(confidence * 100))%)  back=\(Int(pBack * 100)) down=\(Int(pDown * 100)) follow=\(Int(pFollow * 100))")

        // Check for impact transition
        checkForImpact()
    }

    /// Detect swing impact using three strategies (in priority order):
    ///
    /// 1. **Phase transition**: downswing→follow_through probability crossover (best accuracy)
    /// 2. **Backswing fallback**: backswing→follow_through when downswing too brief (~150ms)
    /// 3. **Downswing decay**: backswing→downswing→no_swing when follow_through never fires
    ///    (common from front-facing camera where follow_through pose isn't recognized)
    /// 4. **Backswing decay**: backswing→no_swing when both downswing AND follow_through
    ///    are skipped (very fast swing from certain angles)
    private func checkForImpact() {
        lock.lock()
        let history = Array(predictionHistory.suffix(10))
        let currentTime = history.last?.timestamp ?? 0

        guard currentTime - lastDetectionTime > minDetectionInterval else {
            lock.unlock()
            return
        }
        lock.unlock()

        guard history.count >= 3 else { return }

        // Strategy 1: downswing→follow_through transition
        if let swing = detectPhaseTransition(history: history) {
            fireSwingDetection(swing, method: "phase-transition")
            return
        }

        // Strategy 2: backswing→follow_through (downswing too brief)
        if let swing = detectBackswingToFollow(history: history) {
            fireSwingDetection(swing, method: "backswing-fallback")
            return
        }

        // Strategy 3: downswing→no_swing decay (follow_through not detected)
        if let swing = detectDownswingDecay(history: history) {
            fireSwingDetection(swing, method: "downswing-decay")
            return
        }

        // Strategy 4: backswing→no_swing decay (very fast swing, no downswing/follow detected)
        if let swing = detectBackswingDecay(history: history) {
            fireSwingDetection(swing, method: "backswing-decay")
            return
        }
    }

    private func fireSwingDetection(_ swing: SwingBounds, method: String) {
        lock.lock()
        lastDetectionTime = swing.detectionTime
        predictionHistory.removeAll()
        lock.unlock()

        print("⛳ ActionClassifier SWING [\(method)]: \(String(format: "%.2f", swing.startTime))s -> impact=\(String(format: "%.2f", swing.impactTime))s -> \(String(format: "%.2f", swing.endTime))s  conf=\(Int(swing.confidence * 100))%")
        onSwingDetected?(swing)
    }

    /// Strategy 1: Find downswing→follow_through probability transition
    private func detectPhaseTransition(history: [PredictionRecord]) -> SwingBounds? {
        var lastDownswingRecord: PredictionRecord?
        var firstFollowThroughRecord: PredictionRecord?

        for record in history {
            let pDown = record.probabilities[downswingLabel] ?? 0
            let pFollow = record.probabilities[followThroughLabel] ?? 0

            if pDown >= downswingThreshold {
                lastDownswingRecord = record
                firstFollowThroughRecord = nil
            } else if pFollow >= followThroughThreshold && lastDownswingRecord != nil {
                if firstFollowThroughRecord == nil {
                    firstFollowThroughRecord = record
                }
            }
        }

        guard let downPred = lastDownswingRecord,
              let followPred = firstFollowThroughRecord else { return nil }

        let peakDown = downPred.probabilities[downswingLabel] ?? 0
        let peakFollow = followPred.probabilities[followThroughLabel] ?? 0
        guard (peakDown + peakFollow) >= minSwingConfidence else { return nil }

        let impactTime = estimateImpactTime(downswingPred: downPred, followPred: followPred)
        let swingStart = findSwingStart(in: history, before: downPred.timestamp)

        return SwingBounds(
            startTime: max(0, swingStart - preSwingBuffer),
            impactTime: impactTime,
            endTime: followPred.timestamp + postSwingBuffer,
            confidence: (peakDown + peakFollow) / 2.0,
            detectionTime: followPred.timestamp,
            audioConfirmed: false
        )
    }

    /// Strategy 2: Find backswing→follow_through (skipping downswing)
    private func detectBackswingToFollow(history: [PredictionRecord]) -> SwingBounds? {
        var lastBackswingRecord: PredictionRecord?
        var firstFollowRecord: PredictionRecord?

        for record in history {
            let pBack = record.probabilities[backswingLabel] ?? 0
            let pFollow = record.probabilities[followThroughLabel] ?? 0

            if pBack >= 0.4 {
                lastBackswingRecord = record
                firstFollowRecord = nil
            } else if pFollow >= followThroughThreshold && lastBackswingRecord != nil {
                if firstFollowRecord == nil {
                    firstFollowRecord = record
                }
            }
        }

        guard let backPred = lastBackswingRecord,
              let followPred = firstFollowRecord else { return nil }

        let peakFollow = followPred.probabilities[followThroughLabel] ?? 0
        guard peakFollow >= followThroughThreshold else { return nil }

        // Impact is roughly at the transition point
        let impactTime = (backPred.timestamp + followPred.windowStart) / 2.0

        return SwingBounds(
            startTime: max(0, backPred.windowStart - preSwingBuffer),
            impactTime: impactTime,
            endTime: followPred.timestamp + postSwingBuffer,
            confidence: peakFollow * 0.7,
            detectionTime: followPred.timestamp,
            audioConfirmed: false
        )
    }

    /// Strategy 3: Detect backswing→downswing→no_swing pattern.
    ///
    /// When the model sees a clear downswing that decays to no_swing (without follow_through
    /// ever reaching threshold), this is still a valid swing — common from front-facing cameras
    /// where the follow_through pose isn't recognized.
    /// Requires at least one no_swing after the downswing to confirm the swing ended.
    private func detectDownswingDecay(history: [PredictionRecord]) -> SwingBounds? {
        var lastDownswingRecord: PredictionRecord?
        var confirmedByNoSwing = false

        for record in history {
            let pDown = record.probabilities[downswingLabel] ?? 0
            let pBack = record.probabilities[backswingLabel] ?? 0

            if pDown >= downswingThreshold {
                lastDownswingRecord = record
                confirmedByNoSwing = false
            } else if lastDownswingRecord != nil && record.label == noSwingLabel && pBack < 0.3 {
                // no_swing after downswing (and not just returning to backswing)
                confirmedByNoSwing = true
            }
        }

        guard let downPred = lastDownswingRecord, confirmedByNoSwing else { return nil }

        let peakDown = downPred.probabilities[downswingLabel] ?? 0
        guard peakDown >= 0.40 else { return nil }

        // Impact is near the end of the downswing window
        let impactTime = downPred.timestamp - 0.2
        let swingStart = findSwingStart(in: history, before: downPred.timestamp)

        return SwingBounds(
            startTime: max(0, swingStart - preSwingBuffer),
            impactTime: impactTime,
            endTime: downPred.timestamp + postSwingBuffer,
            confidence: peakDown * 0.6,
            detectionTime: downPred.timestamp + 1.0,
            audioConfirmed: false
        )
    }

    /// Strategy 4: Detect backswing→no_swing when the swing is too fast for the model
    /// to register downswing or follow_through.
    ///
    /// To reduce false positives (e.g. just raising arms), we require:
    /// - Strong backswing (>= 50%)
    /// - Subsequent no_swing with some residual swing signal (downswing or follow_through >= 5%)
    private func detectBackswingDecay(history: [PredictionRecord]) -> SwingBounds? {
        var lastBackswingRecord: PredictionRecord?
        var confirmingRecord: PredictionRecord?

        for record in history {
            let pBack = record.probabilities[backswingLabel] ?? 0
            let pDown = record.probabilities[downswingLabel] ?? 0
            let pFollow = record.probabilities[followThroughLabel] ?? 0

            if pBack >= 0.50 {
                lastBackswingRecord = record
                confirmingRecord = nil
            } else if lastBackswingRecord != nil && record.label == noSwingLabel {
                // Look for residual swing signal — confirms a swing actually happened
                let swingResidual = pDown + pFollow
                if swingResidual >= 0.05 && confirmingRecord == nil {
                    confirmingRecord = record
                }
            }
        }

        guard let backPred = lastBackswingRecord,
              let confirmPred = confirmingRecord else { return nil }

        let peakBack = backPred.probabilities[backswingLabel] ?? 0

        // Impact is roughly between backswing end and confirming prediction
        let impactTime = (backPred.timestamp + confirmPred.windowStart) / 2.0

        return SwingBounds(
            startTime: max(0, backPred.windowStart - preSwingBuffer),
            impactTime: impactTime,
            endTime: confirmPred.timestamp + postSwingBuffer,
            confidence: peakBack * 0.5,
            detectionTime: confirmPred.timestamp,
            audioConfirmed: false
        )
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
