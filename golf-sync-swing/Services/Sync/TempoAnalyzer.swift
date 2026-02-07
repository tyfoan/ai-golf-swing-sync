//
//  TempoAnalyzer.swift
//  golf-sync-swing
//
//  Analyzes swing tempo similarity and calculates speed adjustment
//  for video2 to match video1's timing.
//

import Foundation

struct TempoAnalysis {
    let match: Double       // 0-1, how similar tempos are
    let speedAdjustment: Float  // Playback speed for video2 to match video1
    let duration1: TimeInterval?
    let duration2: TimeInterval?
}

struct TempoAnalyzer {

    func analyze(result1: SwingDetectionResult, result2: SwingDetectionResult) -> TempoAnalysis {
        guard let duration1 = result1.backswingToImpactDuration,
              let duration2 = result2.backswingToImpactDuration,
              duration1 > 0.1, duration2 > 0.1 else {
            return TempoAnalysis(match: 1.0, speedAdjustment: 1.0, duration1: nil, duration2: nil)
        }

        let match = min(duration1, duration2) / max(duration1, duration2)

        var speedRatio = Float(duration2 / duration1)
        speedRatio = max(0.7, min(1.3, speedRatio))
        if abs(speedRatio - 1.0) < 0.08 {
            speedRatio = 1.0
        }

        return TempoAnalysis(
            match: match,
            speedAdjustment: speedRatio,
            duration1: duration1,
            duration2: duration2
        )
    }
}
