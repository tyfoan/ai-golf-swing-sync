//
//  DownswingDecayStrategy.swift
//  golf-sync-swing
//
//  Detects backswing->downswing->no_swing pattern.
//  Common from front-facing cameras where the follow_through pose isn't recognized.
//

import Foundation

struct DownswingDecayStrategy: ImpactDetectionStrategy {

    var name: String { "downswing-decay" }

    private let downswingThreshold: Double = 0.30
    private let minPeakDownswing: Double = 0.40
    private let preSwingBuffer: TimeInterval = 0.8
    private let postSwingBuffer: TimeInterval = 0.8
    private let maxHalfDuration: TimeInterval = 2.0

    func detectImpact(in history: [PredictionRecord]) -> ImpactCandidate? {
        var lastDownswingRecord: PredictionRecord?
        var confirmedByNoSwing = false

        for record in history {
            let pDown = record.probabilities["downswing"] ?? 0
            let pBack = record.probabilities["backswing"] ?? 0

            if pDown >= downswingThreshold {
                lastDownswingRecord = record
                confirmedByNoSwing = false
            } else if lastDownswingRecord != nil && record.label == "no_swing" && pBack < 0.3 {
                confirmedByNoSwing = true
            }
        }

        guard let downPred = lastDownswingRecord, confirmedByNoSwing else { return nil }

        let peakDown = downPred.probabilities["downswing"] ?? 0
        guard peakDown >= minPeakDownswing else { return nil }

        let impactTime = downPred.timestamp - 0.2
        let swingStart = findSwingStart(in: history, before: downPred.timestamp)

        let clampedStart = max(impactTime - maxHalfDuration, swingStart - preSwingBuffer)
        let clampedEnd = min(impactTime + maxHalfDuration, downPred.timestamp + postSwingBuffer)

        let bounds = SwingBounds(
            startTime: max(0, clampedStart),
            impactTime: impactTime,
            endTime: clampedEnd,
            confidence: peakDown * 0.6,
            detectionTime: downPred.timestamp + 1.0,
            audioConfirmed: false
        )

        return ImpactCandidate(swingBounds: bounds, strategy: name)
    }

    private func findSwingStart(in history: [PredictionRecord], before cutoff: TimeInterval) -> TimeInterval {
        var earliest = cutoff
        for record in history where record.timestamp <= cutoff {
            let pBack = record.probabilities["backswing"] ?? 0
            if pBack >= 0.3 && record.windowStart < earliest {
                earliest = record.windowStart
            }
        }
        return earliest
    }
}
