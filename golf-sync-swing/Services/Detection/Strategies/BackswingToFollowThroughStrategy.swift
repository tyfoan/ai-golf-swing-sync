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

    private let config: DetectorConfiguration
    private let preSwingBuffer: TimeInterval = 0.8
    private let postSwingBuffer: TimeInterval = 0.8
    private let maxHalfDuration: TimeInterval = 2.0

    private var backswingThreshold: Double { config.thresholds.backswing }
    private var followThroughThreshold: Double { config.thresholds.followThrough }

    init(configuration: DetectorConfiguration) {
        self.config = configuration
    }

    func detectImpact(in history: [PredictionRecord]) -> ImpactCandidate? {
        var lastBackswingRecord: PredictionRecord?
        var firstFollowRecord: PredictionRecord?

        for record in history {
            let pBack = record.probabilities[config.backswingLabel] ?? 0
            let pFollow = aggregateFollow(record)

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

        let peakFollow = aggregateFollow(followPred)
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

    private func aggregateFollow(_ record: PredictionRecord) -> Double {
        config.followThroughLabels.reduce(0.0) { $0 + (record.probabilities[$1] ?? 0) }
    }
}
