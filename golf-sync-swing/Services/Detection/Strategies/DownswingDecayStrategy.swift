//
//  DownswingDecayStrategy.swift
//  golf-sync-swing
//
//  Detects downswing->noswing pattern.
//  Common from front-facing cameras where the follow_through pose isn't recognized.
//

import Foundation

struct DownswingDecayStrategy: ImpactDetectionStrategy {

    var name: String { "downswing-decay" }

    private let config: DetectorConfiguration
    private let preSwingBuffer: TimeInterval = 0.8
    private let postSwingBuffer: TimeInterval = 0.8
    private let maxHalfDuration: TimeInterval = 2.0

    private var downswingThreshold: Double { config.thresholds.downswingDecay }
    private var minPeakDownswing: Double { config.thresholds.minPeakDownswing }

    init(configuration: DetectorConfiguration) {
        self.config = configuration
    }

    func detectImpact(in history: [PredictionRecord]) -> ImpactCandidate? {
        var lastDownswingRecord: PredictionRecord?
        var confirmedByNoSwing = false

        for record in history {
            let pDown = aggregateDownswing(record)
            let pBack = record.probabilities[config.backswingLabel] ?? 0

            if pDown >= downswingThreshold {
                lastDownswingRecord = record
                confirmedByNoSwing = false
            } else if lastDownswingRecord != nil && record.label == config.noSwingLabel && pBack < 0.15 {
                confirmedByNoSwing = true
            }
        }

        guard let downPred = lastDownswingRecord, confirmedByNoSwing else { return nil }

        let peakDown = aggregateDownswing(downPred)
        guard peakDown >= minPeakDownswing else { return nil }

        let impactTime = downPred.timestamp - 0.1
        let swingStart = findSwingStart(in: history, before: downPred.timestamp)

        let clampedStart = max(impactTime - maxHalfDuration, swingStart - preSwingBuffer)
        let clampedEnd = min(impactTime + maxHalfDuration, downPred.timestamp + postSwingBuffer)

        let bounds = SwingBounds(
            startTime: max(0, clampedStart),
            impactTime: impactTime,
            endTime: clampedEnd,
            confidence: peakDown * 0.6,
            detectionTime: downPred.timestamp + 0.5,
            audioConfirmed: false
        )

        return ImpactCandidate(swingBounds: bounds, strategy: name)
    }

    private func aggregateDownswing(_ record: PredictionRecord) -> Double {
        config.downswingLabels.reduce(0.0) { $0 + (record.probabilities[$1] ?? 0) }
    }

    private func findSwingStart(in history: [PredictionRecord], before cutoff: TimeInterval) -> TimeInterval {
        var earliest = cutoff
        for record in history where record.timestamp <= cutoff {
            let pBack = record.probabilities[config.backswingLabel] ?? 0
            if pBack >= 0.10 && record.windowStart < earliest {
                earliest = record.windowStart
            }
        }
        return earliest
    }
}
