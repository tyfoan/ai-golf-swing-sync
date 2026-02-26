//
//  PoseHeuristics.swift
//  golf-sync-swing
//
//  Fallback swing detection using body pose heuristics.
//  Detects a golf swing by analyzing wrist velocity relative to hip center.
//

import Foundation
import Vision
import os

protocol SwingDetecting: Sendable {
    func analyze(frames: [PoseFrame]) -> SwingEvent
}

struct PoseHeuristics: SwingDetecting {

    private let velocityThreshold: CGFloat = 2.0
    private let minimumDescentFrames: Int = 5
    private let minimumDisplacement: CGFloat = 0.15

    func analyze(frames: [PoseFrame]) -> SwingEvent {
        guard frames.count >= 10 else { return .noSwing }

        guard meetsDisplacementThreshold(frames: frames) else { return .noSwing }

        let velocities = computeWristVelocities(frames: frames)
        let descentCount = velocities.filter { $0 < -velocityThreshold }.count

        guard descentCount >= minimumDescentFrames else { return .noSwing }

        let peakVelocityIndex = velocities.enumerated()
            .min(by: { $0.element < $1.element })?.offset ?? 0
        let timestamp = frames[min(peakVelocityIndex + 1, frames.count - 1)].timestamp
        let confidence = min(1.0, Double(descentCount) / 8.0)

        AppLogger.detection.info("PoseHeuristics: swing detected (descent=\(descentCount) frames, conf=\(String(format: "%.2f", confidence)))")
        return .swingDetected(confidence: confidence, timestamp: timestamp)
    }

    private func meetsDisplacementThreshold(frames: [PoseFrame]) -> Bool {
        let yValues = frames.compactMap { leadWristY(in: $0) }
        guard let maxY = yValues.max(), let minY = yValues.min() else { return false }
        return (maxY - minY) >= minimumDisplacement
    }

    private func computeWristVelocities(frames: [PoseFrame]) -> [CGFloat] {
        guard frames.count >= 2 else { return [] }

        return (1..<frames.count).map { i in
            let prev = frames[i - 1]
            let curr = frames[i]

            let dt = curr.timestamp - prev.timestamp
            guard dt > 0 else { return 0 }

            let prevY = leadWristY(in: prev)
            let currY = leadWristY(in: curr)
            guard let py = prevY, let cy = currY else { return 0 }

            return (cy - py) / dt
        }
    }

    private func leadWristY(in frame: PoseFrame) -> CGFloat? {
        let wrists: [VNHumanBodyPoseObservation.JointName] = [.leftWrist, .rightWrist]
        return wrists.compactMap { frame.joint($0) }
            .filter { $0.confidence > 0.3 }
            .map(\.y)
            .min()
    }
}
