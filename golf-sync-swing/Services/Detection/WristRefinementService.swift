//
//  WristRefinementService.swift
//  golf-sync-swing
//
//  Refines SwingNet's impact frame estimate using wrist trajectory analysis.
//  The lead wrist reaches its lowest y-position at the exact moment of ball
//  impact (biomechanical fact). By analyzing wrist positions in a ±10 frame
//  window around SwingNet's estimate, we can narrow from ±100ms to ±33ms.
//

import CoreVideo
import Vision

// MARK: - Protocol

protocol WristRefining: Sendable {
    func refineImpactTime(
        currentImpactTime: TimeInterval,
        frames: [(CVPixelBuffer, TimeInterval)],
        searchWindow: Int
    ) -> TimeInterval
}

// MARK: - Implementation

struct WristRefinementService: WristRefining {

    private let minimumConfidence: Float = 0.3

    func refineImpactTime(
        currentImpactTime: TimeInterval,
        frames: [(CVPixelBuffer, TimeInterval)],
        searchWindow: Int = 10
    ) -> TimeInterval {
        let impactIndex = closestFrameIndex(to: currentImpactTime, in: frames)
        let searchRange = searchRange(around: impactIndex, window: searchWindow, count: frames.count)
        let candidates = framesInRange(searchRange, from: frames)

        guard let refinedTime = findWristMinimumTime(in: candidates) else {
            return currentImpactTime
        }

        return refinedTime
    }

    // MARK: - Frame Selection

    private func closestFrameIndex(to time: TimeInterval, in frames: [(CVPixelBuffer, TimeInterval)]) -> Int {
        frames.enumerated().min(by: { abs($0.element.1 - time) < abs($1.element.1 - time) })?.offset ?? 0
    }

    private func searchRange(around center: Int, window: Int, count: Int) -> Range<Int> {
        max(0, center - window)..<min(count, center + window + 1)
    }

    private func framesInRange(_ range: Range<Int>, from frames: [(CVPixelBuffer, TimeInterval)]) -> [(CVPixelBuffer, TimeInterval)] {
        Array(frames[range])
    }

    // MARK: - Wrist Analysis

    private func findWristMinimumTime(in frames: [(CVPixelBuffer, TimeInterval)]) -> TimeInterval? {
        var bestTime: TimeInterval?
        var lowestY: CGFloat = .greatestFiniteMagnitude

        for (buffer, timestamp) in frames {
            guard let wristY = extractLowestWristY(from: buffer) else { continue }

            // Vision normalizes y: 0 = bottom, 1 = top
            // Lowest wrist position = smallest y value
            if wristY < lowestY {
                lowestY = wristY
                bestTime = timestamp
            }
        }

        return bestTime
    }

    private func extractLowestWristY(from buffer: CVPixelBuffer) -> CGFloat? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])

        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first else {
            return nil
        }

        let wrists: [VNHumanBodyPoseObservation.JointName] = [.leftWrist, .rightWrist]
        var lowestY: CGFloat?

        for jointName in wrists {
            guard let point = try? observation.recognizedPoint(jointName),
                  point.confidence > minimumConfidence else {
                continue
            }

            let y = point.location.y
            if lowestY == nil || y < lowestY! {
                lowestY = y
            }
        }

        return lowestY
    }
}
