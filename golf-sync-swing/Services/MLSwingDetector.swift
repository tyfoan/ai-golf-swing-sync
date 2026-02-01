//
//  MLSwingDetector.swift
//  golf-sync-swing
//
//  ML-based real-time swing detection using Create ML Action Classifier
//  This is a drop-in replacement for LiveSwingDetector once you have a trained model
//

import Vision
import CoreML
import AVFoundation

/// ML-powered swing detector using trained Action Classifier
/// To use: Train a model with the ml-training scripts, add GolfSwingClassifier.mlmodel to project
final class MLSwingDetector: @unchecked Sendable {

    // MARK: - Configuration

    /// Prediction window size in frames (must match training config)
    /// Model was trained with 60 frames (2 seconds at 30fps)
    private let windowSize: Int = 60

    /// Minimum confidence to trigger swing detection
    private let minConfidence: Double = 0.70

    /// Minimum interval between swing detections (seconds)
    private let minDetectionInterval: TimeInterval = 2.5

    /// Buffer before swing start (seconds)
    private let preSwingBuffer: TimeInterval = 0.5

    /// Buffer after impact (seconds)
    private let postImpactBuffer: TimeInterval = 1.0

    /// Number of keypoints expected by model (18 keypoints)
    private let numKeypoints: Int = 18

    /// Number of features per keypoint (x, y, confidence)
    private let numFeatures: Int = 3

    // MARK: - State

    private let lock = NSLock()

    /// Sliding window of pose observations
    private var poseWindow: [(pose: VNHumanBodyPoseObservation, timestamp: TimeInterval)] = []

    /// Last swing detection timestamp
    private var lastDetectionTime: TimeInterval = -10.0

    /// Current detected phase
    private var currentPhase: String = "idle"

    /// Tracking state (for UI feedback)
    private(set) var isTrackingSwing: Bool = false

    /// Timestamps for swing boundary estimation
    private var backswingStartTime: TimeInterval?
    private var downswingStartTime: TimeInterval?

    // MARK: - ML Model

    private var modelLoaded: Bool = false
    private var loadError: Error?
    private var classifier: GolfSwingClassifier?

    // MARK: - Callback

    /// Called when a complete swing is detected
    var onSwingDetected: (@Sendable (SwingBounds) -> Void)?

    /// Called when phase changes (for debugging/UI)
    var onPhaseChanged: ((_ phase: String, _ confidence: Double) -> Void)?

    // MARK: - Init

    init() {
        loadModel()
    }

    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all  // Use CPU + GPU + Neural Engine for best performance

            classifier = try GolfSwingClassifier(configuration: config)
            modelLoaded = true
            print("✅ ML Swing Detector: Model loaded successfully")

        } catch {
            loadError = error
            modelLoaded = false
            print("❌ ML Swing Detector: Failed to load model - \(error.localizedDescription)")
            print("   Make sure GolfSwingClassifier.mlmodel is added to the Xcode project")
        }
    }

    // MARK: - Public API

    /// Add a pose observation from Vision framework
    /// - Parameters:
    ///   - pose: The detected body pose
    ///   - timestamp: Frame timestamp (relative to recording start)
    func addPose(_ pose: VNHumanBodyPoseObservation, at timestamp: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        // Add to sliding window
        poseWindow.append((pose, timestamp))

        // Trim to window size
        while poseWindow.count > windowSize {
            poseWindow.removeFirst()
        }

        // Need full window for prediction
        guard poseWindow.count >= windowSize else {
            isTrackingSwing = false
            return
        }

        // Check detection interval
        guard timestamp - lastDetectionTime > minDetectionInterval else {
            return
        }

        // Run ML classification
        classifyCurrentWindow(at: timestamp)
    }

    /// Process pixel buffer directly (extracts pose internally)
    func processFrame(_ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) {
        let request = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            guard let observations = request.results as? [VNHumanBodyPoseObservation],
                  let pose = observations.first else {
                return
            }

            self?.addPose(pose, at: timestamp)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }

    /// Reset detector state
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        poseWindow.removeAll()
        lastDetectionTime = -10.0
        currentPhase = "idle"
        isTrackingSwing = false
        backswingStartTime = nil
        downswingStartTime = nil
    }

    // MARK: - Classification

    private func classifyCurrentWindow(at timestamp: TimeInterval) {
        guard modelLoaded, let classifier = classifier else {
            // Fall back to simple heuristic if no model
            fallbackHeuristicDetection(at: timestamp)
            return
        }

        // Convert poses to model input format
        guard let input = preparePoseInput() else {
            print("⚠️ ML Swing Detector: Failed to prepare pose input")
            return
        }

        do {
            // Run prediction
            let prediction = try classifier.prediction(poses: input)

            let predictedClass = prediction.label
            let confidence = prediction.labelProbabilities[predictedClass] ?? 0

            handlePrediction(phase: predictedClass, confidence: confidence, at: timestamp)

        } catch {
            print("❌ ML prediction error: \(error)")
        }
    }

    private func handlePrediction(phase: String, confidence: Double, at timestamp: TimeInterval) {
        // Track phase transitions
        let previousPhase = currentPhase

        if phase != currentPhase && confidence > 0.5 {
            currentPhase = phase
            onPhaseChanged?(phase, confidence)

            // Track swing boundaries
            switch phase {
            case "backswing":
                if previousPhase == "idle" || previousPhase == "no_swing" {
                    backswingStartTime = timestamp
                    isTrackingSwing = true
                }

            case "downswing":
                downswingStartTime = timestamp

            case "follow_through":
                // Swing complete - trigger detection if confident
                if confidence > minConfidence,
                   let backStart = backswingStartTime,
                   let downStart = downswingStartTime {

                    triggerSwingDetection(
                        backswingStart: backStart,
                        downswingStart: downStart,
                        currentTime: timestamp,
                        confidence: confidence
                    )
                }

            case "idle", "no_swing":
                // Reset tracking
                if isTrackingSwing {
                    backswingStartTime = nil
                    downswingStartTime = nil
                    isTrackingSwing = false
                }

            default:
                break
            }
        }
    }

    private func triggerSwingDetection(
        backswingStart: TimeInterval,
        downswingStart: TimeInterval,
        currentTime: TimeInterval,
        confidence: Double
    ) {
        // Calculate swing boundaries
        let startTime = max(0, backswingStart - preSwingBuffer)
        let impactTime = downswingStart + 0.15  // Estimate impact ~150ms into downswing
        let endTime = currentTime + postImpactBuffer

        let swing = SwingBounds(
            startTime: startTime,
            impactTime: impactTime,
            endTime: endTime,
            confidence: confidence,
            detectionTime: currentTime,
            audioConfirmed: false
        )

        // Update state
        lastDetectionTime = currentTime
        backswingStartTime = nil
        downswingStartTime = nil
        isTrackingSwing = false
        currentPhase = "idle"

        // Fire callback
        onSwingDetected?(swing)
    }

    // MARK: - Fallback Heuristic (when no model is loaded)

    private func fallbackHeuristicDetection(at timestamp: TimeInterval) {
        // Simple fallback using wrist velocity
        // This provides basic functionality until model is trained

        guard poseWindow.count >= 10 else { return }

        // Get recent wrist positions
        var wristYPositions: [Double] = []

        for (pose, _) in poseWindow.suffix(10) {
            if let points = try? pose.recognizedPoints(.all),
               let leftWrist = points[.leftWrist],
               let rightWrist = points[.rightWrist],
               leftWrist.confidence > 0.3,
               rightWrist.confidence > 0.3 {
                let avgY = (leftWrist.location.y + rightWrist.location.y) / 2
                wristYPositions.append(avgY)
            }
        }

        guard wristYPositions.count >= 5 else { return }

        // Check for rapid downward motion (potential downswing)
        let firstHalf = wristYPositions.prefix(wristYPositions.count / 2)
        let secondHalf = wristYPositions.suffix(wristYPositions.count / 2)

        let avgFirst = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let avgSecond = secondHalf.reduce(0, +) / Double(secondHalf.count)

        let velocityEstimate = (avgSecond - avgFirst) * 30  // Normalize to per-second

        // Downswing = rapid decrease in Y (remember: Vision Y is 0 at bottom)
        if velocityEstimate < -0.3 {
            isTrackingSwing = true

            // Very simple impact detection
            if velocityEstimate < -0.5 {
                let swing = SwingBounds(
                    startTime: max(0, timestamp - 1.0),
                    impactTime: timestamp,
                    endTime: timestamp + 1.0,
                    confidence: 0.5,  // Low confidence for heuristic
                    detectionTime: timestamp,
                    audioConfirmed: false
                )

                lastDetectionTime = timestamp
                isTrackingSwing = false
                onSwingDetected?(swing)
            }
        }
    }

    // MARK: - Model Input Preparation

    private func preparePoseInput() -> MLMultiArray? {
        // Convert pose window to MLMultiArray format expected by model
        // Model expects shape: (60 frames, 3 features, 18 keypoints)
        // Features: x, y, confidence
        // Keypoints ordered as: nose, neck, right shoulder, right elbow, right wrist,
        //   left shoulder, left elbow, left wrist, right hip, right knee, right ankle,
        //   left hip, left knee, left ankle, right eye, left eye, right ear, left ear

        guard let multiArray = try? MLMultiArray(
            shape: [NSNumber(value: windowSize), NSNumber(value: numFeatures), NSNumber(value: numKeypoints)],
            dataType: .float32
        ) else {
            return nil
        }

        // Map Vision keypoints to model's expected order
        let keypointMapping: [VNHumanBodyPoseObservation.JointName] = [
            .nose,           // 0: nose
            .neck,           // 1: neck
            .rightShoulder,  // 2: right shoulder
            .rightElbow,     // 3: right elbow
            .rightWrist,     // 4: right wrist
            .leftShoulder,   // 5: left shoulder
            .leftElbow,      // 6: left elbow
            .leftWrist,      // 7: left wrist
            .rightHip,       // 8: right hip
            .rightKnee,      // 9: right knee
            .rightAnkle,     // 10: right ankle
            .leftHip,        // 11: left hip
            .leftKnee,       // 12: left knee
            .leftAnkle,      // 13: left ankle
            .rightEye,       // 14: right eye
            .leftEye,        // 15: left eye
            .rightEar,       // 16: right ear
            .leftEar         // 17: left ear
        ]

        // Fill array with pose data
        for (frameIdx, (pose, _)) in poseWindow.enumerated() {
            guard let points = try? pose.recognizedPoints(.all) else { continue }

            for (keypointIdx, jointName) in keypointMapping.enumerated() {
                let point = points[jointName]
                let x = Float(point?.location.x ?? 0)
                let y = Float(point?.location.y ?? 0)
                let conf = Float(point?.confidence ?? 0)

                // Index calculation for shape (frames, features, keypoints)
                // multiArray[frame][feature][keypoint]
                let xIdx = frameIdx * numFeatures * numKeypoints + 0 * numKeypoints + keypointIdx
                let yIdx = frameIdx * numFeatures * numKeypoints + 1 * numKeypoints + keypointIdx
                let confIdx = frameIdx * numFeatures * numKeypoints + 2 * numKeypoints + keypointIdx

                multiArray[xIdx] = NSNumber(value: x)
                multiArray[yIdx] = NSNumber(value: y)
                multiArray[confIdx] = NSNumber(value: conf)
            }
        }

        return multiArray
    }
}
