//
//  LiveSwingDetector.swift
//  golf-sync-swing
//
//  Real-time swing detection using velocity peak detection
//  Detects swings immediately at impact for fast feedback (<500ms)
//

import Foundation
import Combine

/// Detected swing boundaries
@preconcurrency
struct SwingBounds: Sendable {
    nonisolated let id: UUID
    nonisolated let startTime: TimeInterval
    nonisolated let impactTime: TimeInterval
    nonisolated let endTime: TimeInterval
    nonisolated let confidence: Double

    nonisolated init(startTime: TimeInterval, impactTime: TimeInterval, endTime: TimeInterval, confidence: Double) {
        self.id = UUID()
        self.startTime = startTime
        self.impactTime = impactTime
        self.endTime = endTime
        self.confidence = confidence
    }
}

/// Real-time swing detector using velocity peak detection
/// Detects swings immediately when impact signature is found (no waiting)
final class LiveSwingDetector: @unchecked Sendable {

    // MARK: - Configuration

    /// How long to keep pose history (seconds)
    private let historyDuration: TimeInterval = 3.0

    /// Minimum velocity to consider as swing motion (normalized units/second)
    private let swingVelocityThreshold: Double = 0.12

    /// Peak velocity threshold for impact detection
    private let peakVelocityThreshold: Double = 0.25

    /// Minimum time between detected swings (seconds)
    private let minSwingInterval: TimeInterval = 1.0

    /// Time before impact to mark as swing start
    private let preImpactDuration: TimeInterval = 0.8

    /// Time after impact to mark as swing end (estimated, not waited for)
    private let postImpactDuration: TimeInterval = 0.6

    /// Number of frames to confirm peak (at 30fps, 3 frames = 100ms)
    private let peakConfirmationFrames: Int = 3

    /// Velocity smoothing window size
    private let smoothingWindow: Int = 4

    // MARK: - State

    private let lock = NSLock()
    private var poseHistory: [(timestamp: TimeInterval, leftWristY: Double?, rightWristY: Double?)] = []
    private var velocityHistory: [(timestamp: TimeInterval, velocity: Double)] = []
    private var velocityBuffer: [Double] = []
    private var lastSwingDetectedTime: TimeInterval = -10.0

    // Track velocity peak for impact detection
    private var recentPeakVelocity: Double = 0
    private var peakVelocityTime: TimeInterval = 0
    private var framesAfterPeak: Int = 0
    private var isTrackingDownswing = false
    private var downswingStartTime: TimeInterval = 0

    // Track which wrist is active (the one moving more)
    private var activeWristIsLeft: Bool = false
    private var wristSelectionLocked: Bool = false

    // MARK: - Published State

    /// Indicates if currently tracking a potential swing (for adaptive frame processing)
    private(set) var isTrackingSwing: Bool = false

    // MARK: - Callback

    var onSwingDetected: (@Sendable (SwingBounds) -> Void)?

    // MARK: - Public API

    /// Add a new pose observation with both wrist positions
    func addPose(timestamp: TimeInterval, leftWristY: Double?, rightWristY: Double?) {
        lock.lock()
        defer { lock.unlock() }

        // Add to history
        poseHistory.append((timestamp, leftWristY, rightWristY))

        // Trim old entries
        let cutoff = timestamp - historyDuration
        poseHistory.removeAll { $0.timestamp < cutoff }
        velocityHistory.removeAll { $0.timestamp < cutoff }

        // Select active wrist based on motion
        let activeWristY = selectActiveWrist(leftY: leftWristY, rightY: rightWristY)

        guard let wristY = activeWristY else { return }

        // Calculate velocity
        if poseHistory.count >= 2 {
            let prevIndex = poseHistory.count - 2
            let prev = poseHistory[prevIndex]
            let dt = timestamp - prev.timestamp

            if dt > 0.001 {
                // Get previous wrist position (same wrist we're tracking)
                let prevWristY = activeWristIsLeft ? prev.leftWristY : prev.rightWristY

                if let prevY = prevWristY {
                    // Positive velocity = wrist moving up, Negative = wrist moving down
                    let rawVelocity = (wristY - prevY) / dt
                    let smoothedVelocity = smoothVelocity(rawVelocity)
                    velocityHistory.append((timestamp, smoothedVelocity))

                    // Update tracking state
                    isTrackingSwing = isTrackingDownswing

                    // Analyze for swing
                    analyzeForSwing(velocity: smoothedVelocity, at: timestamp)
                }
            }
        }
    }

    /// Legacy single-wrist API (for compatibility)
    func addPose(timestamp: TimeInterval, wristY: Double) {
        addPose(timestamp: timestamp, leftWristY: nil, rightWristY: wristY)
    }

    /// Reset detector state
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        poseHistory.removeAll()
        velocityHistory.removeAll()
        velocityBuffer.removeAll()
        isTrackingDownswing = false
        isTrackingSwing = false
        recentPeakVelocity = 0
        framesAfterPeak = 0
        lastSwingDetectedTime = -10.0
        wristSelectionLocked = false
    }

    // MARK: - Wrist Selection

    /// Select which wrist to track based on motion
    private func selectActiveWrist(leftY: Double?, rightY: Double?) -> Double? {
        // If only one wrist visible, use it
        if leftY == nil && rightY != nil {
            if !wristSelectionLocked { activeWristIsLeft = false }
            return rightY
        }
        if rightY == nil && leftY != nil {
            if !wristSelectionLocked { activeWristIsLeft = true }
            return leftY
        }

        guard let left = leftY, let right = rightY else { return nil }

        // Once tracking a swing, lock wrist selection
        if wristSelectionLocked {
            return activeWristIsLeft ? left : right
        }

        // Compare recent motion of each wrist
        if poseHistory.count >= 3 {
            let recent = poseHistory.suffix(3)
            var leftMotion: Double = 0
            var rightMotion: Double = 0

            let entries = Array(recent)
            for i in 1..<entries.count {
                if let prevLeft = entries[i-1].leftWristY, let currLeft = entries[i].leftWristY {
                    leftMotion += abs(currLeft - prevLeft)
                }
                if let prevRight = entries[i-1].rightWristY, let currRight = entries[i].rightWristY {
                    rightMotion += abs(currRight - prevRight)
                }
            }

            // Use wrist with more motion
            activeWristIsLeft = leftMotion > rightMotion
        }

        return activeWristIsLeft ? left : right
    }

    // MARK: - Velocity Smoothing

    /// Apply moving average smoothing to velocity
    private func smoothVelocity(_ rawVelocity: Double) -> Double {
        velocityBuffer.append(rawVelocity)
        if velocityBuffer.count > smoothingWindow {
            velocityBuffer.removeFirst()
        }
        return velocityBuffer.reduce(0, +) / Double(velocityBuffer.count)
    }

    // MARK: - Analysis

    private func analyzeForSwing(velocity: Double, at currentTime: TimeInterval) {
        // Don't detect too soon after last swing
        if currentTime - lastSwingDetectedTime < minSwingInterval {
            return
        }

        // Detect start of downswing (rapid downward movement)
        // In Vision coordinates: Y increases upward, so downward = negative velocity
        if !isTrackingDownswing && velocity < -swingVelocityThreshold {
            isTrackingDownswing = true
            wristSelectionLocked = true
            downswingStartTime = currentTime
            recentPeakVelocity = velocity
            peakVelocityTime = currentTime
            framesAfterPeak = 0
        }

        // Track peak velocity during downswing
        if isTrackingDownswing {
            // Track the fastest (most negative) velocity
            if velocity < recentPeakVelocity {
                recentPeakVelocity = velocity
                peakVelocityTime = currentTime
                framesAfterPeak = 0
            } else {
                framesAfterPeak += 1
            }

            // IMMEDIATE DETECTION: Fire as soon as peak is confirmed
            // Peak is confirmed when:
            // 1. We had significant velocity (above threshold)
            // 2. Velocity has been decreasing for peakConfirmationFrames
            // 3. Current velocity is less than 80% of peak (deceleration)

            let velocityMagnitude = abs(recentPeakVelocity)
            let currentMagnitude = abs(velocity)
            let hasSignificantPeak = velocityMagnitude > peakVelocityThreshold
            let isDecelerating = currentMagnitude < velocityMagnitude * 0.8
            let peakConfirmed = framesAfterPeak >= peakConfirmationFrames

            if hasSignificantPeak && isDecelerating && peakConfirmed {
                // FIRE IMMEDIATELY - don't wait for follow-through
                fireSwingDetection(impactTime: peakVelocityTime, peakVelocity: velocityMagnitude, at: currentTime)
                return
            }

            // Timeout: if tracking for too long without impact, reset
            if currentTime - downswingStartTime > 1.2 {
                resetSwingState()
            }

            // False positive: if velocity goes significantly positive (upward without impact), reset
            if velocity > swingVelocityThreshold * 0.8 && framesAfterPeak < peakConfirmationFrames {
                resetSwingState()
            }
        }
    }

    private func fireSwingDetection(impactTime: TimeInterval, peakVelocity: Double, at currentTime: TimeInterval) {
        // Calculate confidence based on peak velocity
        let confidence = min(1.0, peakVelocity / 0.6)

        // Calculate swing boundaries
        let startTime = max(0, findSwingStart(before: impactTime))
        // ESTIMATE end time - don't wait for it
        let endTime = impactTime + postImpactDuration

        let swing = SwingBounds(
            startTime: startTime,
            impactTime: impactTime,
            endTime: endTime,
            confidence: confidence
        )

        lastSwingDetectedTime = currentTime
        resetSwingState()

        onSwingDetected?(swing)
    }

    /// Find the swing start time by looking for when significant movement began
    private func findSwingStart(before impactTime: TimeInterval) -> TimeInterval {
        // Look back in velocity history to find when the swing motion started
        let relevantVelocities = velocityHistory.filter {
            $0.timestamp < impactTime && $0.timestamp > impactTime - 2.0
        }

        // Find when velocity first exceeded threshold
        for (index, entry) in relevantVelocities.enumerated() {
            if abs(entry.velocity) > swingVelocityThreshold * 0.5 {
                // Found start of significant movement
                let startIndex = max(0, index - 2)
                if startIndex < relevantVelocities.count {
                    return relevantVelocities[startIndex].timestamp - 0.2
                }
                return entry.timestamp - 0.3
            }
        }

        // Fallback: use fixed duration before impact
        return impactTime - preImpactDuration
    }

    private func resetSwingState() {
        isTrackingDownswing = false
        isTrackingSwing = false
        recentPeakVelocity = 0
        framesAfterPeak = 0
        wristSelectionLocked = false
        velocityBuffer.removeAll()
    }
}
