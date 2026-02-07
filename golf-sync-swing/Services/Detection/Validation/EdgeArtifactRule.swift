//
//  EdgeArtifactRule.swift
//  golf-sync-swing
//
//  Rejects impact detections at the edges of the frame window
//  (likely artifacts, not real impacts).
//

import Foundation

struct EdgeArtifactRule: SwingValidationRule {

    var name: String { "edge-artifact" }

    func validate(_ analysis: SwingNetAnalysis) -> ValidationResult {
        if analysis.impactProb >= 0.30 {
            guard analysis.impactFrame > 3 && analysis.impactFrame < 61 else {
                return .fail(reason: "impact at edge frame \(analysis.impactFrame) (high conf)")
            }
        } else {
            guard analysis.impactFrame > 16 && analysis.impactFrame < 48 else {
                return .fail(reason: "impact at edge frame \(analysis.impactFrame) (low conf)")
            }
        }
        return .pass
    }
}
