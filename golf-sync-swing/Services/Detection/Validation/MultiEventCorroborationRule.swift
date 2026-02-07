//
//  MultiEventCorroborationRule.swift
//  golf-sync-swing
//
//  Validates that at least one corroborating event (address or top)
//  has meaningful probability — impact alone is not enough.
//

import Foundation

struct MultiEventCorroborationRule: SwingValidationRule {

    var name: String { "multi-event-corroboration" }
    let threshold: Float

    init(threshold: Float = 0.10) {
        self.threshold = threshold
    }

    func validate(_ analysis: SwingNetAnalysis) -> ValidationResult {
        let addressProb = analysis.eventPeaks[.address]?.prob ?? 0
        let topProb = analysis.eventPeaks[.top]?.prob ?? 0

        if addressProb < threshold && topProb < threshold {
            return .fail(reason: "no corroborating events (address=\(Int(addressProb * 100))%, top=\(Int(topProb * 100))%)")
        }
        return .pass
    }
}
