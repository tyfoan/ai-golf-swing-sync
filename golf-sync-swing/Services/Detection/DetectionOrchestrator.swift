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
    private let isActiveLock = NSLock()
    private let processingQueue = DispatchQueue(
        label: "com.golfsync.detection",
        qos: .userInitiated
    )

    /// First frame's host-clock timestamp, used to normalize all detection
    /// timestamps to recording-relative values (file timeline starts at 0).
    private var baseTimestamp: TimeInterval?

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
        isActiveLock.lock()
        isActive = true
        baseTimestamp = nil
        isActiveLock.unlock()
        poseDetector.clearBuffer()
        stateMachine.reset()
        AppLogger.detection.info("DetectionOrchestrator: started")
    }

    func stop() {
        processingQueue.sync {
            self.isActiveLock.lock()
            self.isActive = false
            self.isActiveLock.unlock()
        }
        poseDetector.clearBuffer()
        AppLogger.detection.info("DetectionOrchestrator: stopped")
    }

    // MARK: - Frame Processing

    func processFrame(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        // Normalize host-clock timestamps to recording-relative (0-based).
        // AVCaptureMovieFileOutput writes a zero-based timeline, so detection
        // timestamps must match the file's timeline for seek/playback.
        isActiveLock.lock()
        let active = isActive
        if active && baseTimestamp == nil { baseTimestamp = timestamp }
        let base = baseTimestamp ?? 0
        isActiveLock.unlock()
        guard active else { return }

        let relativeTimestamp = timestamp - base

        processingQueue.async { [weak self] in
            self?.handleFrame(pixelBuffer: pixelBuffer, timestamp: relativeTimestamp)
        }
    }

    private func handleFrame(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        let _ = poseDetector.processFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)

        // Skip detection during cooldown — just buffer frames for impact analysis.
        // isInCooldown(at:) auto-transitions to .idle once cooldownDuration elapses.
        guard !stateMachine.isInCooldown(at: timestamp) else { return }

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

        // Heuristics-primary: classifier is broken (always outputs "swing"),
        // so heuristics drives detection. Classifier acts as optional confidence boost.
        guard case .swingDetected(let hc, let ht) = heuristicsResult else {
            return .noSwing
        }

        let classifierResult = classifier.analyze(frames: frames)
        let boostedConfidence: Double = {
            guard classifier.isAvailable,
                  case .swingDetected = classifierResult else { return hc }
            return min(1.0, hc + 0.15)
        }()

        return .swingDetected(confidence: boostedConfidence, timestamp: ht)
    }
}
