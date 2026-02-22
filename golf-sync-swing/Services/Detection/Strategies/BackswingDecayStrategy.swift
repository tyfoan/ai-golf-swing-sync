//
//  BackswingDecayStrategy.swift
//  golf-sync-swing
//
//  Detects backswing->noswing when the swing is too fast for the model
//  to register downswing or follow_through. Requires residual swing signal
//  in the confirming noswing prediction to reduce false positives.
//

import Foundation

struct BackswingDecayStrategy: ImpactDetectionStrategy {

    var name: String { "backswing-decay" }

    private let config: DetectorConfiguration
    private let minSwingResidual: Double = 0.05
    private let preSwingBuffer: TimeInterval = 0.8
    private let postSwingBuffer: TimeInterval = 0.8
    private let maxHalfDuration: TimeInterval = 2.0

    private var minBackswingProb: Double { config.thresholds.minBackswingProb }

    init(configuration: DetectorConfiguration) {
        self.config = configuration
    }

    func detectImpact(in history: [PredictionRecord]) -> ImpactCandidate? {
        var lastBackswingRecord: PredictionRecord?
        var confirmingRecord: PredictionRecord?

        for record in history {
            let pBack = record.probabilities[config.backswingLabel] ?? 0

            if pBack >= minBackswingProb {
                lastBackswingRecord = record
                confirmingRecord = nil
            } else if lastBackswingRecord != nil && record.label == config.noSwingLabel {
                let residual = swingResidual(record)
                if residual >= minSwingResidual && confirmingRecord == nil {
                    confirmingRecord = record
                }
            }
        }

        guard let backPred = lastBackswingRecord,
              let confirmPred = confirmingRecord else { return nil }

        let peakBack = backPred.probabilities[config.backswingLabel] ?? 0
        let impactTime = (backPred.timestamp + confirmPred.windowStart) / 2.0

        let clampedStart = max(impactTime - maxHalfDuration, backPred.windowStart - preSwingBuffer)
        let clampedEnd = min(impactTime + maxHalfDuration, confirmPred.timestamp + postSwingBuffer)

        let bounds = SwingBounds(
            startTime: max(0, clampedStart),
            impactTime: impactTime,
            endTime: clampedEnd,
            confidence: peakBack * 0.5,
            detectionTime: confirmPred.timestamp,
            audioConfirmed: false
        )

        return ImpactCandidate(swingBounds: bounds, strategy: name)
    }

    private func swingResidual(_ record: PredictionRecord) -> Double {
        let labels = config.downswingLabels + config.followThroughLabels
        return labels.reduce(0.0) { $0 + (record.probabilities[$1] ?? 0) }
    }
}
