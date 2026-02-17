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

    private let minBackswingProb: Double = 0.50
    private let minSwingResidual: Double = 0.05
    private let preSwingBuffer: TimeInterval = 0.8
    private let postSwingBuffer: TimeInterval = 0.8
    private let maxHalfDuration: TimeInterval = 2.0

    func detectImpact(in history: [PredictionRecord]) -> ImpactCandidate? {
        var lastBackswingRecord: PredictionRecord?
        var confirmingRecord: PredictionRecord?

        for record in history {
            let pBack = record.probabilities["backswing"] ?? 0

            if pBack >= minBackswingProb {
                lastBackswingRecord = record
                confirmingRecord = nil
            } else if lastBackswingRecord != nil && record.label == "noswing" {
                let swingResidual = swingProbability(record)
                if swingResidual >= minSwingResidual && confirmingRecord == nil {
                    confirmingRecord = record
                }
            }
        }

        guard let backPred = lastBackswingRecord,
              let confirmPred = confirmingRecord else { return nil }

        let peakBack = backPred.probabilities["backswing"] ?? 0
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

    private func swingProbability(_ record: PredictionRecord) -> Double {
        let pEDown = record.probabilities["early_downswing"] ?? 0
        let pLDown = record.probabilities["late_downswing"] ?? 0
        let pEFol = record.probabilities["early_follow"] ?? 0
        let pFol = record.probabilities["follow_through"] ?? 0
        return pEDown + pLDown + pEFol + pFol
    }
}
