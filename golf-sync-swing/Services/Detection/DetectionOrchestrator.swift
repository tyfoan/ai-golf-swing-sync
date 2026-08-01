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

    /// Every analysed frame's skeleton, for the live overlay. Delivered on the main queue.
    ///
    /// Leave nil when the overlay is hidden — that skips the per-frame main-queue hop
    /// entirely rather than posting 30 updates/sec that nothing draws.
    ///
    /// Lock-protected: unlike `onSwingDetected` (read on main inside a `DispatchQueue.main.async`)
    /// this one is read directly on `processingQueue` for every frame, while the skeleton toggle
    /// writes it from the main actor. That is an unsynchronised cross-thread read/write of a
    /// closure. The getter copies out so the closure is called with the lock released.
    var onPoseDetected: ((BodyJointMap) -> Void)? {
        get { poseCallbackLock.withLock { _onPoseDetected } }
        set { poseCallbackLock.withLock { _onPoseDetected = newValue } }
    }

    private let poseCallbackLock = NSLock()
    private var _onPoseDetected: ((BodyJointMap) -> Void)?

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
    /// Bumped by every start(). Frames carry the session they were captured in,
    /// so a stale frame surviving a stop()/start() bails instead of polluting
    /// the fresh session's buffer, state machine, or callbacks.
    private var sessionID: UInt64 = 0
    private let isActiveLock = NSLock()
    private let processingQueue = DispatchQueue(
        label: "com.golfsync.detection",
        qos: .userInitiated
    )

    /// Backpressure gate. We drop new frames at intake if a previous frame
    /// is still queued or executing on processingQueue. Without this the
    /// async dispatch piles up CVPixelBuffers in FigSharedMemPool whenever
    /// Vision latency spikes (thermal throttle), causing visible stutter.
    private let inFlightLock = NSLock()
    private var inFlight: Int = 0
    private let heuristicsConfidenceFloor: Double = 0.7

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
        sessionID &+= 1
        baseTimestamp = nil
        isActiveLock.unlock()
        inFlightLock.lock()
        inFlight = 0
        inFlightLock.unlock()
        poseDetector.clearBuffer()
        stateMachine.reset()
        AppLogger.detection.info("DetectionOrchestrator: started")
    }

    func stop(caller: String = #function, file: String = #fileID) {
        // Flag first: queued frames bail at handleFrame's session guard, and both
        // callbacks re-check the session on main before delivering, so nothing
        // reaches a listener once stop() has run.
        isActiveLock.lock()
        isActive = false
        isActiveLock.unlock()
        // No sync barrier: every caller is main-actor, and under thermal throttle
        // one in-flight Vision pass runs 100-300 ms — draining synchronously would
        // park the main thread for all of it. The serial queue still orders this
        // cleanup behind any in-flight frame, so the buffer's ~90 retained pose
        // observations are released deterministically without blocking the caller.
        processingQueue.async { [poseDetector] in
            poseDetector.clearBuffer()
        }
        AppLogger.detection.info("DetectionOrchestrator: stopped (caller=\(caller) file=\(file))")
    }

    /// True while the session a frame was captured in is still the live one.
    /// Delivery sites re-check this on the main queue: stop() only runs on the
    /// main actor, so a main-queue check ordered after stop() reliably observes
    /// isActive == false and suppresses the callback.
    private func isCurrentSession(_ session: UInt64) -> Bool {
        isActiveLock.withLock { isActive && session == sessionID }
    }

    // MARK: - Frame Processing

    func processFrame(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        // Normalize host-clock timestamps to recording-relative (0-based).
        // AVCaptureMovieFileOutput writes a zero-based timeline, so detection
        // timestamps must match the file's timeline for seek/playback.
        isActiveLock.lock()
        let active = isActive
        let session = sessionID
        if active && baseTimestamp == nil { baseTimestamp = timestamp }
        let base = baseTimestamp ?? 0
        isActiveLock.unlock()
        guard active else { return }

        let relativeTimestamp = timestamp - base

        inFlightLock.lock()
        let canAccept = inFlight == 0
        if canAccept { inFlight = 1 }
        inFlightLock.unlock()

        guard canAccept else { return }

        processingQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.inFlightLock.lock()
                self.inFlight = 0
                self.inFlightLock.unlock()
            }
            self.handleFrame(pixelBuffer: pixelBuffer, timestamp: relativeTimestamp, session: session)
        }
    }

    private func handleFrame(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, session: UInt64) {
        // Bail early if stop() was called while this frame was queued — a queued
        // backlog must not burn a full Vision pass per frame after the user taps
        // Stop.
        guard isCurrentSession(session) else { return }

        let poseFrame = poseDetector.extractPose(from: pixelBuffer, at: timestamp)

        // Re-check after the Vision pass (100-300 ms under thermal throttle):
        // stop() no longer drains this queue, so a stop()/start() pair can
        // complete mid-pass, and a stale frame must not reach the fresh
        // session's buffer, overlay, or state machine.
        guard isCurrentSession(session) else { return }

        poseDetector.appendToBuffer(poseFrame)

        // Publish the skeleton HERE, above every early return below. Emitting it after the
        // cooldown guard would freeze the overlay for the full 4s cooldown after each
        // detected swing, and after the window guard it would not appear until 15 frames in.
        if onPoseDetected != nil {
            let jointMap = BodyJointMap(frame: poseFrame)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrentSession(session) else { return }
                self.onPoseDetected?(jointMap)
            }
        }

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
            guard let self, self.isCurrentSession(session) else { return }
            self.onSwingDetected?(clip)
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

        // Skip the classifier when heuristics is already confident — the
        // classifier allocates a fresh [MLMultiArray] per call, and at the
        // +0.15 boost we'd be capping at 1.0 anyway.
        guard hc < heuristicsConfidenceFloor else {
            return .swingDetected(confidence: hc, timestamp: ht)
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
