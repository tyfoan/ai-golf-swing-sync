//
//  LiveSwingDetector.swift
//  golf-sync-swing
//
//  Real-time swing detection using pose velocity analysis
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

/// Real-time swing detector using sliding window analysis
final class LiveSwingDetector: @unchecked Sendable {

    // MARK: - Configuration

    /// How long to keep pose history (seconds)
    private let historyDuration: TimeInterval = 4.0

    /// Minimum velocity to detect swing start (normalized units/second)
    private let movementThreshold: Double = 0.08

    /// Velocity threshold for impact (fast downward movement)
    private let impactVelocityThreshold: Double = 0.25

    /// Acceleration threshold for impact (sudden deceleration)
    private let impactAccelerationThreshold: Double = 0.15

    /// Minimum time between detected swings (seconds)
    private let minSwingInterval: TimeInterval = 2.0

    /// Time to wait after impact to determine swing end
    private let postImpactWindow: TimeInterval = 0.8

    // MARK: - State

    private let lock = NSLock()
    private var poseHistory: [(timestamp: TimeInterval, wristY: Double)] = []
    private var velocityHistory: [(timestamp: TimeInterval, velocity: Double)] = []

    private var isInSwing = false
    private var swingStartTime: TimeInterval?
    private var lastSwingDetectedTime: TimeInterval = 0

    private var pendingImpact: (time: TimeInterval, confidence: Double)?

    // MARK: - Callback

    var onSwingDetected: (@Sendable (SwingBounds) -> Void)?

    // MARK: - Public API

    /// Add a new pose observation
    func addPose(timestamp: TimeInterval, wristY: Double) {
        lock.lock()
        defer { lock.unlock() }

        // Add to history
        poseHistory.append((timestamp, wristY))

        // Trim old entries
        let cutoff = timestamp - historyDuration
        poseHistory.removeAll { $0.timestamp < cutoff }
        velocityHistory.removeAll { $0.timestamp < cutoff }

        // Calculate velocity
        if poseHistory.count >= 2 {
            let prev = poseHistory[poseHistory.count - 2]
            let curr = poseHistory[poseHistory.count - 1]
            let dt = curr.timestamp - prev.timestamp

            if dt > 0 {
                let velocity = (curr.wristY - prev.wristY) / dt
                velocityHistory.append((timestamp, velocity))
            }
        }

        // Analyze for swing
        analyzeSwing(at: timestamp)
    }

    /// Reset detector state
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        poseHistory.removeAll()
        velocityHistory.removeAll()
        isInSwing = false
        swingStartTime = nil
        pendingImpact = nil
    }

    // MARK: - Analysis

    private func analyzeSwing(at currentTime: TimeInterval) {
        // Don't detect too soon after last swing
        if currentTime - lastSwingDetectedTime < minSwingInterval {
            return
        }

        guard velocityHistory.count >= 5 else { return }

        // Check for swing start
        if !isInSwing {
            detectSwingStart(at: currentTime)
        }

        // Check for impact
        if isInSwing && pendingImpact == nil {
            detectImpact(at: currentTime)
        }

        // Check for swing end after impact
        if let impact = pendingImpact {
            detectSwingEnd(impactTime: impact.time, impactConfidence: impact.confidence, at: currentTime)
        }
    }

    private func detectSwingStart(at currentTime: TimeInterval) {
        let recentVelocities = velocityHistory.suffix(5)

        // Calculate average absolute velocity
        let avgAbsVelocity = recentVelocities.map { abs($0.velocity) }.reduce(0, +) / Double(recentVelocities.count)

        if avgAbsVelocity > movementThreshold {
            // Movement detected - mark swing start
            isInSwing = true
            // Start is slightly before current time
            swingStartTime = currentTime - 0.3
        }
    }

    private func detectImpact(at currentTime: TimeInterval) {
        guard let startTime = swingStartTime else { return }
        guard velocityHistory.count >= 3 else { return }

        let recent = velocityHistory.suffix(3)
        let velocities = Array(recent.map { $0.velocity })

        // Calculate acceleration (change in velocity)
        let acceleration = velocities.count >= 2
            ? velocities[velocities.count - 1] - velocities[velocities.count - 2]
            : 0

        let currentVelocity = velocities.last ?? 0

        // Impact signature:
        // - Fast downward movement (negative velocity in normalized coords, but wrist goes DOWN)
        // - Sudden deceleration (velocity becoming less negative)
        let isDownward = currentVelocity < -impactVelocityThreshold
        let isDecelerating = acceleration > impactAccelerationThreshold

        if isDownward && isDecelerating {
            // Calculate confidence
            let velocityScore = min(1.0, abs(currentVelocity) / 0.8)
            let accelScore = min(1.0, acceleration / 0.5)
            let confidence = (velocityScore + accelScore) / 2

            pendingImpact = (currentTime, confidence)
        }

        // Timeout: if no impact within 2.5 seconds of start, reset
        if currentTime - startTime > 2.5 {
            resetSwingState()
        }
    }

    private func detectSwingEnd(impactTime: TimeInterval, impactConfidence: Double, at currentTime: TimeInterval) {
        // Wait for post-impact window
        guard currentTime - impactTime >= postImpactWindow else { return }

        guard let startTime = swingStartTime else {
            resetSwingState()
            return
        }

        // Check if movement has settled
        let recentVelocities = velocityHistory.suffix(3)
        let avgAbsVelocity = recentVelocities.map { abs($0.velocity) }.reduce(0, +) / Double(max(1, recentVelocities.count))

        let hasSettled = avgAbsVelocity < movementThreshold * 1.5
        let enoughTimePassed = currentTime - impactTime >= postImpactWindow

        if hasSettled || enoughTimePassed {
            // Swing complete
            let swing = SwingBounds(
                startTime: startTime,
                impactTime: impactTime,
                endTime: currentTime,
                confidence: impactConfidence
            )

            lastSwingDetectedTime = currentTime
            onSwingDetected?(swing)
            resetSwingState()
        }

        // Timeout: end swing after 1.5 seconds regardless
        if currentTime - impactTime > 1.5 {
            let swing = SwingBounds(
                startTime: startTime,
                impactTime: impactTime,
                endTime: currentTime,
                confidence: impactConfidence * 0.8
            )

            lastSwingDetectedTime = currentTime
            onSwingDetected?(swing)
            resetSwingState()
        }
    }

    private func resetSwingState() {
        isInSwing = false
        swingStartTime = nil
        pendingImpact = nil
    }
}
