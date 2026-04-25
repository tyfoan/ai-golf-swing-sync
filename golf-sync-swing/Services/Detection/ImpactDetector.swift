//
//  ImpactDetector.swift
//  golf-sync-swing
//
//  Velocity-first impact detection validated against 55 GolfDB videos:
//    1. Compute all frame-to-frame wrist velocities
//    2. Find the first significant downward velocity burst (the downswing)
//    3. Impact = Y minimum in a small window after the burst
//
//  Falls back to naive global Y-minimum when velocity approach lacks data.
//

import Foundation
import Vision
import os

protocol ImpactDetecting: Sendable {
    func findImpactTime(in frames: [PoseFrame]) -> TimeInterval?
}

struct ImpactDetector: ImpactDetecting {

    private let minimumConfidence: Float = 0.3
    private let downswingVelocityThreshold: CGFloat = -0.5
    private let postPeakWindowSize: Int = 6

    func findImpactTime(in frames: [PoseFrame]) -> TimeInterval? {
        velocityFirstImpact(in: frames) ?? naiveFallback(in: frames)
    }

    // MARK: - Velocity-First Detection

    private func velocityFirstImpact(in frames: [PoseFrame]) -> TimeInterval? {
        let rawWristData = extractWristData(from: frames)
        guard rawWristData.count >= 10 else { return nil }

        // Median-smooth for velocity computation (filters single-frame noise spikes)
        let smoothed = medianSmoothed(from: rawWristData)

        let minY = smoothed.map(\.y).min() ?? 0
        let maxY = smoothed.map(\.y).max() ?? 0
        let yRange = maxY - minY
        guard yRange >= 0.05 else { return nil }

        let velocities = computeVelocities(from: smoothed)
        guard !velocities.isEmpty else { return nil }

        // Only count downswing after wrist has risen above 40% of its range
        // (skip early velocity spikes before the backswing has happened)
        let riseThreshold = minY + yRange * 0.4
        var hasRisen = false

        // Find the first sustained downward velocity AFTER a backswing.
        // Require the next velocity to also be negative to filter single-frame noise.
        guard let firstDownswing = velocities.first(where: { entry in
            let currentY = smoothed[entry.dataIndex].y
            let prevY = smoothed[entry.dataIndex - 1].y
            if prevY >= riseThreshold { hasRisen = true }
            guard hasRisen && entry.vel < downswingVelocityThreshold
                    && currentY > minY + yRange * 0.15 else { return false }
            let nextIndex = velocities.firstIndex(where: { $0.dataIndex == entry.dataIndex + 1 })
            guard let next = nextIndex else { return true }
            return velocities[next].vel < 0
        }) else {
            // Fallback: try without the rise gate for short clips
            guard let ungated = velocities.first(where: { $0.vel < downswingVelocityThreshold }) else {
                return nil
            }
            // Use raw data for Y-minimum impact search (preserves timing accuracy)
            return findImpactAfterPeak(ungated: ungated, velocities: velocities, wristData: rawWristData)
        }

        // Use raw data for Y-minimum impact search (preserves timing accuracy)
        return findImpactAfterPeak(
            ungated: firstDownswing, velocities: velocities, wristData: rawWristData
        )
    }

    private func findImpactAfterPeak(
        ungated: VelocityEntry,
        velocities: [VelocityEntry],
        wristData: [WristEntry]
    ) -> TimeInterval? {
        // Find the peak (most negative) velocity near the burst
        let burstEnd = min(ungated.dataIndex + 8, wristData.count)
        let burstVelocities = velocities.filter {
            $0.dataIndex >= ungated.dataIndex && $0.dataIndex < burstEnd
        }
        guard let peakVel = burstVelocities.min(by: { $0.vel < $1.vel }) else {
            return nil
        }

        // Impact: Y minimum in a small window after peak velocity
        let searchStart = peakVel.dataIndex
        let searchEnd = min(wristData.count, searchStart + postPeakWindowSize)
        let searchWindow = Array(wristData[searchStart..<searchEnd])

        guard let impact = searchWindow.min(by: { $0.y < $1.y }) else { return nil }

        AppLogger.detection.info(
            "ImpactDetector: velocity-first at \(String(format: "%.3f", impact.time))s (peakVel=\(String(format: "%.3f", peakVel.time))s, v=\(String(format: "%.2f", peakVel.vel)))"
        )
        return impact.time
    }

    // MARK: - Naive Fallback

    private func naiveFallback(in frames: [PoseFrame]) -> TimeInterval? {
        var bestTime: TimeInterval?
        var lowestY: CGFloat = .greatestFiniteMagnitude

        for frame in frames {
            guard let wristY = leadWristY(in: frame) else { continue }
            if wristY < lowestY {
                lowestY = wristY
                bestTime = frame.timestamp
            }
        }

        if let time = bestTime {
            AppLogger.detection.info("ImpactDetector: naive fallback at \(String(format: "%.3f", time))s")
        }
        return bestTime
    }

    // MARK: - Helpers

    private struct WristEntry {
        let dataIndex: Int
        let time: TimeInterval
        let y: CGFloat
    }

    private struct VelocityEntry {
        let dataIndex: Int
        let time: TimeInterval
        let vel: CGFloat
    }

    private func extractWristData(from frames: [PoseFrame]) -> [WristEntry] {
        var entries: [WristEntry] = []
        for (i, frame) in frames.enumerated() {
            guard let y = leadWristY(in: frame) else { continue }
            entries.append(WristEntry(dataIndex: i, time: frame.timestamp, y: y))
        }
        return entries
    }

    private func medianSmoothed(from wristData: [WristEntry]) -> [WristEntry] {
        guard wristData.count >= 3 else { return wristData }
        var smoothed = [wristData[0]]
        for i in 1..<(wristData.count - 1) {
            let trio = [wristData[i - 1].y, wristData[i].y, wristData[i + 1].y].sorted()
            smoothed.append(WristEntry(dataIndex: wristData[i].dataIndex, time: wristData[i].time, y: trio[1]))
        }
        smoothed.append(wristData[wristData.count - 1])
        return smoothed
    }

    private func computeVelocities(from wristData: [WristEntry]) -> [VelocityEntry] {
        guard wristData.count >= 2 else { return [] }
        return (1..<wristData.count).compactMap { i in
            let dt = wristData[i].time - wristData[i - 1].time
            guard dt > 0 else { return nil }
            let vel = (wristData[i].y - wristData[i - 1].y) / dt
            return VelocityEntry(dataIndex: i, time: wristData[i].time, vel: vel)
        }
    }

    private func leadWristY(in frame: PoseFrame) -> CGFloat? {
        let wristNames: [VNHumanBodyPoseObservation.JointName] = [.leftWrist, .rightWrist]
        let yValues = wristNames.compactMap { name -> CGFloat? in
            guard let joint = frame.joint(name),
                  joint.confidence > minimumConfidence else { return nil }
            return joint.y
        }
        return yValues.min()
    }
}
