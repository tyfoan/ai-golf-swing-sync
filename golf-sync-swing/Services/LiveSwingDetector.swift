//
//  LiveSwingDetector.swift
//  golf-sync-swing
//
//  STRICT real-time swing detection designed to minimize false positives
//  Requires clear backswing arc, fast downswing, and proper timing
//

import Foundation

// MARK: - Swing Phase State Machine

/// Golf swing phases for live detection state machine
enum LiveSwingPhase: String, Sendable {
    case idle           // Waiting for swing to start
    case watching       // Detected motion, watching to confirm backswing
    case backswing      // Confirmed backswing in progress
    case top            // At top of backswing
    case downswing      // Fast downward motion
}

// MARK: - Pose Frame Data

/// Multi-joint pose data for a single frame
struct PoseFrame: Sendable {
    let timestamp: TimeInterval
    let leftWristY: Double?
    let rightWristY: Double?
    let leftShoulderY: Double?
    let rightShoulderY: Double?
    let leftShoulderX: Double?
    let rightShoulderX: Double?
    let leftHipY: Double?
    let rightHipY: Double?
    let leftHipX: Double?
    let rightHipX: Double?

    /// Check if both wrists are visible
    var bothWristsVisible: Bool {
        leftWristY != nil && rightWristY != nil
    }

    /// Average wrist Y position (requires both wrists for reliability)
    var avgWristY: Double? {
        guard let left = leftWristY, let right = rightWristY else {
            // Fallback to single wrist if only one visible
            return leftWristY ?? rightWristY
        }
        return (left + right) / 2
    }

    /// Check if both wrists are moving together (similar Y positions)
    var wristsMovingTogether: Bool {
        guard let left = leftWristY, let right = rightWristY else { return false }
        // Wrists should be within 15% of each other during a golf swing
        return abs(left - right) < 0.15
    }
}

// MARK: - Swing Bounds

/// Detected swing boundaries
@preconcurrency
struct SwingBounds: Sendable {
    nonisolated let id: UUID
    nonisolated let startTime: TimeInterval
    nonisolated let impactTime: TimeInterval
    nonisolated let endTime: TimeInterval
    nonisolated let confidence: Double
    nonisolated let detectionTime: TimeInterval
    nonisolated let audioConfirmed: Bool

    nonisolated init(
        startTime: TimeInterval,
        impactTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Double,
        detectionTime: TimeInterval,
        audioConfirmed: Bool = false
    ) {
        self.id = UUID()
        self.startTime = startTime
        self.impactTime = impactTime
        self.endTime = endTime
        self.confidence = confidence
        self.detectionTime = detectionTime
        self.audioConfirmed = audioConfirmed
    }
}

// MARK: - Live Swing Detector

/// STRICT real-time swing detector - designed to minimize false positives
/// Requires: significant backswing arc, fast downswing, proper timing, both wrists moving
final class LiveSwingDetector: @unchecked Sendable {

    // MARK: - STRICT Configuration (tuned to reduce false positives)

    /// Minimum backswing arc height (normalized units, 0-1 scale)
    /// A real golf swing raises hands significantly - at least 10-15% of frame height
    private let minBackswingArc: Double = 0.10

    /// Minimum backswing duration (seconds)
    /// Real backswing takes 0.5-1.5s, not instant
    private let minBackswingDuration: TimeInterval = 0.4

    /// Maximum backswing duration (seconds)
    private let maxBackswingDuration: TimeInterval = 2.5

    /// Minimum peak downswing velocity (normalized units/second)
    /// Golf downswing is FAST - this filters out slow arm movements
    private let minDownswingVelocity: Double = 0.30

    /// Downswing must be at least this much faster than backswing avg velocity
    private let downswingSpeedRatio: Double = 2.0

    /// Maximum downswing duration (seconds)
    /// Golf downswing is very quick - 0.2-0.4s
    private let maxDownswingDuration: TimeInterval = 0.5

    /// Minimum total swing duration (backswing + downswing)
    private let minTotalSwingDuration: TimeInterval = 0.7

    /// Minimum time between detected swings (seconds)
    private let minSwingInterval: TimeInterval = 2.5

    /// Frames to confirm velocity peak has passed
    private let peakConfirmationFrames: Int = 2

    /// Post-impact buffer for clip (seconds)
    private let postImpactBuffer: TimeInterval = 1.0

    /// History duration (seconds)
    private let historyDuration: TimeInterval = 4.0

    /// Velocity smoothing window
    private let smoothingWindow: Int = 4

    // MARK: - State

    private let lock = NSLock()
    private var poseHistory: [PoseFrame] = []
    private var velocityBuffer: [Double] = []
    private var lastSwingDetectedTime: TimeInterval = -10.0

    // State machine
    private var currentPhase: LiveSwingPhase = .idle
    private var phaseStartTime: TimeInterval = 0

    // Swing tracking
    private var swingStartTime: TimeInterval = 0
    private var swingStartY: Double = 0
    private var backswingPeakY: Double = 0
    private var backswingPeakTime: TimeInterval = 0
    private var backswingAvgVelocity: Double = 0
    private var downswingStartTime: TimeInterval = 0
    private var peakDownVelocity: Double = 0
    private var peakVelocityTime: TimeInterval = 0
    private var framesAfterPeak: Int = 0

    // Audio
    private var pendingAudioImpact: TimeInterval?

    // MARK: - Published State

    private(set) var isTrackingSwing: Bool = false

    // MARK: - Callback

    var onSwingDetected: (@Sendable (SwingBounds) -> Void)?

    // MARK: - Public API

    /// Add pose observation
    func addPose(_ frame: PoseFrame) {
        lock.lock()
        defer { lock.unlock() }

        poseHistory.append(frame)

        // Trim old entries
        let cutoff = frame.timestamp - historyDuration
        poseHistory.removeAll { $0.timestamp < cutoff }

        // Need at least 2 frames
        guard poseHistory.count >= 2 else { return }

        // Calculate velocity
        let velocity = calculateSmoothedVelocity()

        // Update tracking state
        isTrackingSwing = currentPhase != .idle

        // Run state machine
        updateStateMachine(frame: frame, velocity: velocity)
    }

    /// Legacy API
    func addPose(timestamp: TimeInterval, leftWristY: Double?, rightWristY: Double?) {
        let frame = PoseFrame(
            timestamp: timestamp,
            leftWristY: leftWristY,
            rightWristY: rightWristY,
            leftShoulderY: nil, rightShoulderY: nil,
            leftShoulderX: nil, rightShoulderX: nil,
            leftHipY: nil, rightHipY: nil,
            leftHipX: nil, rightHipX: nil
        )
        addPose(frame)
    }

    /// Audio impact confirmation
    func confirmAudioImpact(at timestamp: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        pendingAudioImpact = timestamp
    }

    /// Reset detector
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        poseHistory.removeAll()
        velocityBuffer.removeAll()
        currentPhase = .idle
        isTrackingSwing = false
        lastSwingDetectedTime = -10.0
        pendingAudioImpact = nil
        resetSwingTracking()
    }

    // MARK: - Velocity Calculation

    private func calculateSmoothedVelocity() -> Double {
        guard poseHistory.count >= 2 else { return 0 }

        let current = poseHistory[poseHistory.count - 1]
        let previous = poseHistory[poseHistory.count - 2]

        let dt = current.timestamp - previous.timestamp
        guard dt > 0.001 else { return 0 }

        // Get average wrist Y
        guard let currentY = current.avgWristY, let previousY = previous.avgWristY else {
            return 0
        }

        let rawVelocity = (currentY - previousY) / dt

        // Smooth
        velocityBuffer.append(rawVelocity)
        if velocityBuffer.count > smoothingWindow {
            velocityBuffer.removeFirst()
        }

        return velocityBuffer.reduce(0, +) / Double(velocityBuffer.count)
    }

    // MARK: - State Machine

    private func updateStateMachine(frame: PoseFrame, velocity: Double) {
        let currentTime = frame.timestamp

        // Enforce minimum interval between swings
        if currentTime - lastSwingDetectedTime < minSwingInterval {
            if currentPhase != .idle {
                resetToIdle()
            }
            return
        }

        // Get wrist position
        guard let avgY = frame.avgWristY else {
            // Lost tracking in early phases = reset
            if currentPhase == .idle || currentPhase == .watching {
                resetToIdle()
            }
            return
        }

        switch currentPhase {
        case .idle:
            // Look for upward motion that could be backswing start
            // Require moderate upward velocity AND preferably both wrists visible
            if velocity > 0.06 {
                currentPhase = .watching
                phaseStartTime = currentTime
                swingStartTime = currentTime
                swingStartY = avgY
                backswingPeakY = avgY
                backswingPeakTime = currentTime
            }

        case .watching:
            // Confirm this is a real backswing, not just arm fidgeting
            let elapsed = currentTime - phaseStartTime

            // Track peak
            if avgY > backswingPeakY {
                backswingPeakY = avgY
                backswingPeakTime = currentTime
            }

            let arcHeight = backswingPeakY - swingStartY

            // STRICT: Confirm backswing only if we have significant arc
            if arcHeight >= minBackswingArc && elapsed >= 0.25 {
                currentPhase = .backswing
                backswingAvgVelocity = arcHeight / elapsed
            }

            // Reject: not enough arc after reasonable time
            if elapsed > 0.6 && arcHeight < minBackswingArc * 0.6 {
                resetToIdle()
            }

            // Reject: velocity went very negative before establishing arc
            if velocity < -0.20 && arcHeight < minBackswingArc * 0.5 {
                resetToIdle()
            }

        case .backswing:
            let duration = currentTime - swingStartTime

            // Track peak
            if avgY > backswingPeakY {
                backswingPeakY = avgY
                backswingPeakTime = currentTime
            }

            // Update average velocity
            let arcHeight = backswingPeakY - swingStartY
            if duration > 0 {
                backswingAvgVelocity = arcHeight / duration
            }

            // Detect transition to top/downswing
            let timeSincePeak = currentTime - backswingPeakTime

            // Top of backswing: peak was reached, now moving down
            if duration >= minBackswingDuration &&
               timeSincePeak > 0.06 &&
               velocity < -0.08 &&
               arcHeight >= minBackswingArc {
                currentPhase = .top
                phaseStartTime = currentTime
            }

            // Timeout
            if duration > maxBackswingDuration {
                resetToIdle()
            }

        case .top:
            // Quick transition to downswing when velocity is strongly negative
            if velocity < -minDownswingVelocity * 0.4 {
                currentPhase = .downswing
                downswingStartTime = currentTime
                peakDownVelocity = velocity
                peakVelocityTime = currentTime
                framesAfterPeak = 0
            }

            // Timeout at top
            if currentTime - phaseStartTime > 0.35 {
                resetToIdle()
            }

        case .downswing:
            let downDuration = currentTime - downswingStartTime
            let totalDuration = currentTime - swingStartTime

            // Track peak velocity (most negative)
            if velocity < peakDownVelocity {
                peakDownVelocity = velocity
                peakVelocityTime = currentTime
                framesAfterPeak = 0
            } else {
                framesAfterPeak += 1
            }

            let peakSpeed = abs(peakDownVelocity)
            let currentSpeed = abs(velocity)

            // === IMPACT DETECTION - ALL CRITERIA MUST BE MET ===

            // 1. Peak velocity is high enough (fast downswing)
            let hasFastDownswing = peakSpeed >= minDownswingVelocity

            // 2. Downswing is significantly faster than backswing
            let isFasterThanBackswing = backswingAvgVelocity > 0 &&
                                        peakSpeed >= backswingAvgVelocity * downswingSpeedRatio

            // 3. Velocity is now decelerating (past peak)
            let isDecelerating = currentSpeed < peakSpeed * 0.55

            // 4. Peak confirmed for enough frames
            let peakConfirmed = framesAfterPeak >= peakConfirmationFrames

            // 5. Wrists have returned close to starting position
            let arcHeight = backswingPeakY - swingStartY
            let returnDistance = avgY - swingStartY
            let inImpactZone = arcHeight > 0.01 && (returnDistance / arcHeight) < 0.40

            // 6. Total duration is reasonable
            let validDuration = totalDuration >= minTotalSwingDuration

            // FIRE only if ALL criteria met
            if hasFastDownswing && isFasterThanBackswing && isDecelerating &&
               peakConfirmed && inImpactZone && validDuration {
                fireSwingDetection(impactTime: peakVelocityTime, at: currentTime)
                return
            }

            // Timeout
            if downDuration > maxDownswingDuration {
                resetToIdle()
            }

            // Abort if velocity reverses
            if velocity > 0.10 && framesAfterPeak < peakConfirmationFrames {
                resetToIdle()
            }
        }
    }

    private func fireSwingDetection(impactTime: TimeInterval, at currentTime: TimeInterval) {
        // Audio confirmation
        var audioConfirmed = false
        if let audioTime = pendingAudioImpact, abs(audioTime - impactTime) < 0.12 {
            audioConfirmed = true
        }

        // Calculate confidence
        let peakSpeed = abs(peakDownVelocity)
        let arcHeight = backswingPeakY - swingStartY

        var confidence = 0.50
        confidence += min(0.20, (peakSpeed - minDownswingVelocity) * 0.5)
        confidence += min(0.15, (arcHeight - minBackswingArc) * 1.0)
        if audioConfirmed { confidence += 0.15 }
        confidence = min(1.0, max(0.40, confidence))

        // Clip boundaries
        let startTime = max(0, swingStartTime - 0.4)
        let endTime = impactTime + postImpactBuffer

        let swing = SwingBounds(
            startTime: startTime,
            impactTime: impactTime,
            endTime: endTime,
            confidence: confidence,
            detectionTime: currentTime,
            audioConfirmed: audioConfirmed
        )

        lastSwingDetectedTime = currentTime
        pendingAudioImpact = nil
        resetToIdle()

        onSwingDetected?(swing)
    }

    private func resetToIdle() {
        currentPhase = .idle
        isTrackingSwing = false
        resetSwingTracking()
    }

    private func resetSwingTracking() {
        velocityBuffer.removeAll()
        swingStartY = 0
        backswingPeakY = 0
        backswingPeakTime = 0
        backswingAvgVelocity = 0
        peakDownVelocity = 0
        peakVelocityTime = 0
        framesAfterPeak = 0
    }
}
