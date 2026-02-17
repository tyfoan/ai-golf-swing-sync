//
//  DownswingToFollowThroughStrategy.swift
//  golf-sync-swing
//
//  Primary impact detection: finds the late_downswing->early_follow probability transition.
//  The boundary between these two phases IS the impact frame.
//

import Foundation

struct DownswingToFollowThroughStrategy: ImpactDetectionStrategy {

    var name: String { "phase-transition" }

    private let lateDownswingThreshold: Double = 0.25
    private let earlyFollowThreshold: Double = 0.25
    private let minSwingConfidence: Double = 0.35
    private let crossoverMinProb: Double = 0.05
    private let preSwingBuffer: TimeInterval = 0.8
    private let postSwingBuffer: TimeInterval = 0.8
    private let maxHalfDuration: TimeInterval = 2.0
    private let predictionWindow: Int = 15

    func detectImpact(in history: [PredictionRecord]) -> ImpactCandidate? {
        let transition = findTransition(in: history)
        guard let transition else { return nil }

        let peakDown = transition.downswingRecord.probabilities["late_downswing"] ?? 0
        let peakFollow = transition.followThroughRecord.probabilities["early_follow"] ?? 0
        guard (peakDown + peakFollow) >= minSwingConfidence else { return nil }

        let impactTime = estimateImpactTime(from: history, fallbackDown: transition.downswingRecord)
        let swingStart = findSwingStart(in: history, before: transition.downswingRecord.timestamp)

        let clampedStart = max(impactTime - maxHalfDuration, swingStart - preSwingBuffer)
        let clampedEnd = min(impactTime + maxHalfDuration, transition.followThroughRecord.timestamp + postSwingBuffer)

        let bounds = SwingBounds(
            startTime: max(0, clampedStart),
            impactTime: impactTime,
            endTime: clampedEnd,
            confidence: (peakDown + peakFollow) / 2.0,
            detectionTime: transition.followThroughRecord.timestamp,
            audioConfirmed: false
        )

        return ImpactCandidate(swingBounds: bounds, strategy: name)
    }

    // MARK: - Transition Detection

    private struct Transition {
        let downswingRecord: PredictionRecord
        let followThroughRecord: PredictionRecord
    }

    private func findTransition(in history: [PredictionRecord]) -> Transition? {
        var lastDownswing: PredictionRecord?
        var firstFollow: PredictionRecord?

        for record in history {
            let pLateDown = record.probabilities["late_downswing"] ?? 0
            let pEarlyDown = record.probabilities["early_downswing"] ?? 0
            let pEarlyFollow = record.probabilities["early_follow"] ?? 0

            let pDownswing = pLateDown + pEarlyDown

            if pLateDown >= lateDownswingThreshold || pDownswing >= 0.40 {
                lastDownswing = record
                firstFollow = nil
            } else if pEarlyFollow >= earlyFollowThreshold && lastDownswing != nil {
                if firstFollow == nil {
                    firstFollow = record
                }
            }
        }

        guard let down = lastDownswing, let follow = firstFollow else { return nil }
        return Transition(downswingRecord: down, followThroughRecord: follow)
    }

    // MARK: - Impact Time Estimation (crossover interpolation)

    private func estimateImpactTime(from history: [PredictionRecord], fallbackDown: PredictionRecord) -> TimeInterval {
        let windowDuration = Double(predictionWindow) / 30.0
        let estimates = collectCrossoverEstimates(from: history, windowDuration: windowDuration)

        guard !estimates.isEmpty else {
            return fallbackDown.timestamp - 0.1
        }

        return weightedAverage(estimates)
    }

    /// Each record where both P(late_downswing) and P(early_follow) are non-zero
    /// gives an independent impact estimate. Records closer to the 50/50
    /// crossover are weighted higher — they straddle the impact frame most evenly.
    private func collectCrossoverEstimates(
        from history: [PredictionRecord],
        windowDuration: TimeInterval
    ) -> [(time: TimeInterval, weight: Double)] {
        var estimates: [(time: TimeInterval, weight: Double)] = []

        for record in history {
            let pDown = record.probabilities["late_downswing"] ?? 0
            let pFollow = record.probabilities["early_follow"] ?? 0
            let total = pDown + pFollow

            guard total > minSwingConfidence else { continue }
            guard pDown > crossoverMinProb, pFollow > crossoverMinProb else { continue }

            let fractionPreImpact = pDown / total
            let estimatedImpact = record.windowStart + windowDuration * (1.0 - fractionPreImpact)
            let crossoverProximity = 1.0 - abs(fractionPreImpact - 0.5) * 2.0
            let weight = total * max(crossoverProximity, 0.1)

            estimates.append((time: estimatedImpact, weight: weight))
        }

        return estimates
    }

    private func weightedAverage(_ estimates: [(time: TimeInterval, weight: Double)]) -> TimeInterval {
        let totalWeight = estimates.reduce(0.0) { $0 + $1.weight }
        let weightedSum = estimates.reduce(0.0) { $0 + $1.time * $1.weight }
        return weightedSum / totalWeight
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
