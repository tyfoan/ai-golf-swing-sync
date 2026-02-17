//
//  BackswingToFollowThroughStrategy.swift
//  golf-sync-swing
//
//  Fallback impact detection for fast swings where the downswing phases
//  are too brief to register: backswing->follow_through transition.
//

import Foundation

struct BackswingToFollowThroughStrategy: ImpactDetectionStrategy {

    var name: String { "backswing-fallback" }

    private let backswingThreshold: Double = 0.40
    private let followThroughThreshold: Double = 0.30
    private let preSwingBuffer: TimeInterval = 0.8
    private let postSwingBuffer: TimeInterval = 0.8
    private let maxHalfDuration: TimeInterval = 2.0

    func detectImpact(in history: [PredictionRecord]) -> ImpactCandidate? {
        var lastBackswingRecord: PredictionRecord?
        var firstFollowRecord: PredictionRecord?

        for record in history {
            let pBack = record.probabilities["backswing"] ?? 0
            let pFollow = followProbability(record)

            if pBack >= backswingThreshold {
                lastBackswingRecord = record
                firstFollowRecord = nil
            } else if pFollow >= followThroughThreshold && lastBackswingRecord != nil {
                if firstFollowRecord == nil {
                    firstFollowRecord = record
                }
            }
        }

        guard let backPred = lastBackswingRecord,
              let followPred = firstFollowRecord else { return nil }

        let peakFollow = followProbability(followPred)
        guard peakFollow >= followThroughThreshold else { return nil }

        let impactTime = (backPred.timestamp + followPred.windowStart) / 2.0

        let clampedStart = max(impactTime - maxHalfDuration, backPred.windowStart - preSwingBuffer)
        let clampedEnd = min(impactTime + maxHalfDuration, followPred.timestamp + postSwingBuffer)

        let bounds = SwingBounds(
            startTime: max(0, clampedStart),
            impactTime: impactTime,
            endTime: clampedEnd,
            confidence: peakFollow * 0.7,
            detectionTime: followPred.timestamp,
            audioConfirmed: false
        )

        return ImpactCandidate(swingBounds: bounds, strategy: name)
    }

    private func followProbability(_ record: PredictionRecord) -> Double {
        let pFollow = record.probabilities["follow_through"] ?? 0
        let pEarlyFollow = record.probabilities["early_follow"] ?? 0
        return pFollow + pEarlyFollow
    }
}
