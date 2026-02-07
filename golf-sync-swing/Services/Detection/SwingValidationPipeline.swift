//
//  SwingValidationPipeline.swift
//  golf-sync-swing
//
//  Composite validation: runs all SwingValidationRules in sequence.
//  Returns the first failure reason, or nil if all rules pass.
//

import Foundation

struct SwingValidationPipeline {

    private let rules: [SwingValidationRule]

    init(rules: [SwingValidationRule]) {
        self.rules = rules
    }

    static func `default`() -> SwingValidationPipeline {
        SwingValidationPipeline(rules: [
            ImpactConfidenceRule(),
            EdgeArtifactRule(),
            NoEventDominanceRule(),
            TemporalOrderRule(),
            MultiEventCorroborationRule(),
        ])
    }

    func validate(_ analysis: SwingNetAnalysis) -> String? {
        for rule in rules {
            if case .fail(let reason) = rule.validate(analysis) {
                return reason
            }
        }
        return nil
    }
}
