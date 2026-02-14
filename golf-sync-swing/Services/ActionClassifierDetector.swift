//
//  ActionClassifierDetector.swift
//  golf-sync-swing
//
//  Pose-based swing detector using 4-class Create ML Action Classifier.
//  Angle-independent: works from any camera position (front, side, behind).
//
//  Delegates to collaborators:
//    PoseExtractor      - Vision framework body pose detection
//    PoseFrameBuffer    - Thread-safe sliding window of pose keypoints
//    PhaseClassifier    - CoreML 4-class swing phase prediction
//    ImpactDetectionChain - Polymorphic impact detection strategies
//

import AVFoundation
import Foundation
import os

final class ActionClassifierDetector: @unchecked Sendable {

    // MARK: - Configuration

    private let predictionWindow: Int = 60
    private let idleStride: Int = 15
    private let activeStride: Int = 8
    private let minDetectionInterval: TimeInterval = 3.0
    private let maxHistorySize: Int = 30

    private let backswingLabel = "backswing"
    private let downswingLabel = "downswing"
    private let followThroughLabel = "follow_through"

    // MARK: - Collaborators

    private let poseExtractor: PoseExtracting
    private let phaseClassifier: PhaseClassifying
    private let poseBuffer: PoseFrameBuffer
    private let impactChain: ImpactDetectionChain
    let posePublisher: PosePublisher

    // MARK: - State

    private let lock = NSLock()
    private var predictionHistory: [PredictionRecord] = []
    private var frameCounter: Int = 0
    private var totalFramesProcessed: Int = 0
    private var classificationCount: Int = 0
    private var classificationStride: Int = 15
    private var lastDetectionTime: TimeInterval = -10.0
    private var consecutiveNoPoseFrames: Int = 0
    private let noPoseIdleThreshold: Int = 30

    // MARK: - Public State

    private(set) var isTrackingSwing: Bool = false
    private(set) var isMotionDetected: Bool = false

    // MARK: - Callbacks

    var onSwingDetected: (@Sendable (SwingBounds) -> Void)?
    var onPhaseChanged: ((_ phase: String, _ confidence: Double) -> Void)?

    // MARK: - Init

    init(
        poseExtractor: PoseExtracting = PoseExtractor(),
        phaseClassifier: PhaseClassifying = PhaseClassifier(),
        poseBuffer: PoseFrameBuffer = PoseFrameBuffer(capacity: 60),
        impactChain: ImpactDetectionChain = .default(),
        posePublisher: PosePublisher = PosePublisher()
    ) {
        self.poseExtractor = poseExtractor
        self.phaseClassifier = phaseClassifier
        self.poseBuffer = poseBuffer
        self.impactChain = impactChain
        self.posePublisher = posePublisher
    }

    // MARK: - Public API

    func processFrame(_ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) {
        guard (phaseClassifier as? PhaseClassifier)?.isLoaded ?? true else {
            lock.lock()
            totalFramesProcessed += 1
            lock.unlock()
            return
        }

        lock.lock()
        totalFramesProcessed += 1
        lock.unlock()

        guard let result = poseExtractor.extractPose(from: pixelBuffer, at: timestamp) else {
            posePublisher.publish(nil)
            lock.lock()
            consecutiveNoPoseFrames += 1
            if consecutiveNoPoseFrames > noPoseIdleThreshold {
                isMotionDetected = false
                classificationStride = idleStride
            }
            lock.unlock()
            return
        }

        posePublisher.publish(result.jointMap)

        lock.lock()
        consecutiveNoPoseFrames = 0
        isMotionDetected = true
        lock.unlock()

        poseBuffer.append(PoseFrame(timestamp: timestamp, keypointsArray: result.multiArray))

        lock.lock()
        guard timestamp - lastDetectionTime > minDetectionInterval else {
            lock.unlock()
            return
        }

        frameCounter += 1
        let currentStride = classificationStride
        let shouldClassify = frameCounter >= currentStride && poseBuffer.isFull
        if shouldClassify { frameCounter = 0 }
        lock.unlock()

        guard shouldClassify else { return }
        let frames = poseBuffer.snapshot(last: predictionWindow)
        runClassification(frames: frames)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        poseBuffer.clear()
        predictionHistory.removeAll()
        frameCounter = 0
        totalFramesProcessed = 0
        classificationCount = 0
        lastDetectionTime = -10.0
        isTrackingSwing = false
        isMotionDetected = false
        consecutiveNoPoseFrames = 0
        classificationStride = idleStride
        AppLogger.detection.debug("ActionClassifierDetector: Reset")
    }

    // MARK: - Classification

    private func runClassification(frames: [PoseFrame]) {
        guard let record = phaseClassifier.classify(frames: frames, predictionWindow: predictionWindow) else {
            return
        }

        let confidence = record.probabilities[record.label] ?? 0

        lock.lock()
        classificationCount += 1
        let currentCount = classificationCount
        predictionHistory.append(record)
        if predictionHistory.count > maxHistorySize {
            predictionHistory.removeFirst()
        }

        let isActiveSwing = (record.label == downswingLabel || record.label == followThroughLabel || record.label == backswingLabel)
        isTrackingSwing = isActiveSwing
        classificationStride = isActiveSwing ? activeStride : idleStride
        lock.unlock()

        onPhaseChanged?(record.label, confidence)

        let pDown = record.probabilities[downswingLabel] ?? 0
        let pFollow = record.probabilities[followThroughLabel] ?? 0
        let pBack = record.probabilities[backswingLabel] ?? 0
        AppLogger.detection.debug("ActionClassifier[\(currentCount)]: \(record.label) (\(Int(confidence * 100))%)  back=\(Int(pBack * 100)) down=\(Int(pDown * 100)) follow=\(Int(pFollow * 100))")

        checkForImpact()
    }

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

        if let candidate = impactChain.detect(in: history) {
            lock.lock()
            lastDetectionTime = candidate.swingBounds.detectionTime
            predictionHistory.removeAll()
            lock.unlock()

            let swing = candidate.swingBounds
            AppLogger.detection.info("ActionClassifier SWING [\(candidate.strategy)]: \(String(format: "%.2f", swing.startTime))s -> impact=\(String(format: "%.2f", swing.impactTime))s -> \(String(format: "%.2f", swing.endTime))s  conf=\(Int(swing.confidence * 100))%")
            onSwingDetected?(swing)
        }
    }
}
