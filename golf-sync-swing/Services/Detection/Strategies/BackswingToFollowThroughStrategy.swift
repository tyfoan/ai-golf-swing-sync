//
//  BackswingToFollowThroughStrategy.swift
//  golf-sync-swing
//
//  Fallback impact detection for fast swings where the downswing phase
//  is too brief (~150ms) to register: backswing->follow_through transition.
//

import Foundation

struct BackswingToFollowThroughStrategy: ImpactDetectionStrategy {

    var name: String { "backswing-fallback" }

    private let backswingThreshold: Double = 0.40
    private let followThroughThreshold: Double = 0.30
    private let preSwingBuffer: TimeInterval = 1.5
    private let postSwingBuffer: TimeInterval = 1.5

    func detectImpact(in history: [PredictionRecord]) -> ImpactCandidate? {
        var lastBackswingRecord: PredictionRecord?
        var firstFollowRecord: PredictionRecord?

        for record in history {
            let pBack = record.probabilities["backswing"] ?? 0
            let pFollow = record.probabilities["follow_through"] ?? 0

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

        let peakFollow = followPred.probabilities["follow_through"] ?? 0
        guard peakFollow >= followThroughThreshold else { return nil }

        let impactTime = (backPred.timestamp + followPred.windowStart) / 2.0

        let bounds = SwingBounds(
            startTime: max(0, backPred.windowStart - preSwingBuffer),
            impactTime: impactTime,
            endTime: followPred.timestamp + postSwingBuffer,
            confidence: peakFollow * 0.7,
            detectionTime: followPred.timestamp,
            audioConfirmed: false
        )

        return ImpactCandidate(swingBounds: bounds, strategy: name)
    }
}
