//
//  ImpactConfidenceRule.swift
//  golf-sync-swing
//
//  Validates that impact confidence meets the minimum threshold.
//

import Foundation

struct ImpactConfidenceRule: SwingValidationRule {

    var name: String { "impact-confidence" }
    let threshold: Float

    init(threshold: Float = 0.15) {
        self.threshold = threshold
    }

    func validate(_ analysis: SwingNetAnalysis) -> ValidationResult {
        if analysis.impactProb < threshold {
            return .fail(reason: "impact confidence too low (\(Int(analysis.impactProb * 100))% < \(Int(threshold * 100))%)")
        }
        return .pass
    }
}
