//
//  DownswingToFollowThroughStrategy.swift
//  golf-sync-swing
//
//  Primary impact detection: finds the downswing->follow_through probability transition.
//  This is the most accurate strategy when the model clearly sees both phases.
//

import Foundation

struct DownswingToFollowThroughStrategy: ImpactDetectionStrategy {

    var name: String { "phase-transition" }

    private let downswingThreshold: Double = 0.30
    private let followThroughThreshold: Double = 0.30
    private let minSwingConfidence: Double = 0.40
    private let preSwingBuffer: TimeInterval = 1.5
    private let postSwingBuffer: TimeInterval = 1.5
    private let predictionWindow: Int = 60

    func detectImpact(in history: [PredictionRecord]) -> ImpactCandidate? {
        var lastDownswingRecord: PredictionRecord?
        var firstFollowThroughRecord: PredictionRecord?

        for record in history {
            let pDown = record.probabilities["downswing"] ?? 0
            let pFollow = record.probabilities["follow_through"] ?? 0

            if pDown >= downswingThreshold {
                lastDownswingRecord = record
                firstFollowThroughRecord = nil
            } else if pFollow >= followThroughThreshold && lastDownswingRecord != nil {
                if firstFollowThroughRecord == nil {
                    firstFollowThroughRecord = record
                }
            }
        }

        guard let downPred = lastDownswingRecord,
              let followPred = firstFollowThroughRecord else { return nil }

        let peakDown = downPred.probabilities["downswing"] ?? 0
        let peakFollow = followPred.probabilities["follow_through"] ?? 0
        guard (peakDown + peakFollow) >= minSwingConfidence else { return nil }

        let impactTime = estimateImpactTime(downswingPred: downPred, followPred: followPred)
        let swingStart = findSwingStart(in: history, before: downPred.timestamp)

        let bounds = SwingBounds(
            startTime: max(0, swingStart - preSwingBuffer),
            impactTime: impactTime,
            endTime: followPred.timestamp + postSwingBuffer,
            confidence: (peakDown + peakFollow) / 2.0,
            detectionTime: followPred.timestamp,
            audioConfirmed: false
        )

        return ImpactCandidate(swingBounds: bounds, strategy: name)
    }

    private func estimateImpactTime(downswingPred: PredictionRecord, followPred: PredictionRecord) -> TimeInterval {
        let windowDuration = Double(predictionWindow) / 30.0

        let pDown = followPred.probabilities["downswing"] ?? 0
        let pFollow = followPred.probabilities["follow_through"] ?? 0

        if pDown > 0.1 && pFollow > 0.1 {
            let fraction = pDown / (pDown + pFollow)
            return followPred.windowStart + windowDuration * (1.0 - fraction)
        }

        return downswingPred.timestamp - 0.3
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
