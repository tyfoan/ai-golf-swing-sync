//
//  DetectionOrchestrator.swift
//  golf-sync-swing
//
//  Wires the real-time detection pipeline:
//    CameraService.onFrameCaptured → PoseDetector → SwingClassifier/PoseHeuristics
//    → SwingStateMachine → ImpactDetector → SwingClip
//
//  Processes every frame on a background queue. Emits detected swings
//  via the onSwingDetected callback.
//

import CoreVideo
import Foundation
import os

final class DetectionOrchestrator: @unchecked Sendable {

    // MARK: - Callbacks

    var onSwingDetected: ((SwingClip) -> Void)?

    // MARK: - Collaborators

    private let poseDetector: PoseDetector
    private let classifier: SwingClassifier
    private let heuristics: PoseHeuristics
    private let stateMachine: SwingStateMachine
    private let impactDetector: ImpactDetecting

    // MARK: - Configuration

    private let analysisWindowSize: Int = 15
    private let clipPaddingBefore: TimeInterval = 0.5
    private let clipPaddingAfter: TimeInterval = 0.5

    // MARK: - State

    private var isActive = false
    private let processingQueue = DispatchQueue(
        label: "com.golfsync.detection",
        qos: .userInitiated
    )

    init(
        poseDetector: PoseDetector = PoseDetector(),
        classifier: SwingClassifier = SwingClassifier(),
        heuristics: PoseHeuristics = PoseHeuristics(),
        stateMachine: SwingStateMachine = SwingStateMachine(cooldownDuration: 4.0),
        impactDetector: ImpactDetecting = ImpactDetector()
    ) {
        self.poseDetector = poseDetector
        self.classifier = classifier
        self.heuristics = heuristics
        self.stateMachine = stateMachine
        self.impactDetector = impactDetector
    }

    // MARK: - Lifecycle

    func start() {
        isActive = true
        poseDetector.clearBuffer()
        stateMachine.reset()
        AppLogger.detection.info("DetectionOrchestrator: started")
    }

    func stop() {
        isActive = false
        AppLogger.detection.info("DetectionOrchestrator: stopped")
    }

    // MARK: - Frame Processing

    func processFrame(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        guard isActive else { return }

        processingQueue.async { [weak self] in
            self?.handleFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
    }

    private func handleFrame(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        let _ = poseDetector.processFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        let recentFrames = poseDetector.recentFrames(count: analysisWindowSize)

        guard recentFrames.count >= analysisWindowSize else { return }

        let event = detectSwing(in: recentFrames)

        guard let detection = stateMachine.handle(event: event) else { return }

        let swingFrames = poseDetector.recentFrames(count: 90)
        let impactTime = impactDetector.findImpactTime(in: swingFrames) ?? detection.detectionTimestamp

        let startTime = max(0, impactTime - 1.0 - clipPaddingBefore)
        let endTime = impactTime + 0.5 + clipPaddingAfter

        let clip = SwingClip(
            startTime: startTime,
            impactTime: impactTime,
            endTime: endTime,
            confidence: detection.confidence,
            detectionTime: detection.detectionTimestamp
        )

        stateMachine.transitionToReplay(
            impactTime: impactTime,
            startTime: startTime,
            endTime: endTime
        )

        AppLogger.detection.info("Swing detected: impact=\(String(format: "%.2f", impactTime))s, clip=\(String(format: "%.1f", startTime))-\(String(format: "%.1f", endTime))s")

        DispatchQueue.main.async { [weak self] in
            self?.onSwingDetected?(clip)
        }
    }

    // MARK: - Strategy Selection

    private func detectSwing(in frames: [PoseFrame]) -> SwingEvent {
        let heuristicsResult = heuristics.analyze(frames: frames)
        let classifierResult = classifier.analyze(frames: frames)

        // Consensus: both must detect a swing to reduce false positives.
        // If classifier is unavailable, heuristics alone suffices.
        if classifier.isAvailable {
            guard case .swingDetected(let cc, let ct) = classifierResult,
                  case .swingDetected = heuristicsResult else {
                return .noSwing
            }
            return .swingDetected(confidence: cc, timestamp: ct)
        }

        return heuristicsResult
    }
}
