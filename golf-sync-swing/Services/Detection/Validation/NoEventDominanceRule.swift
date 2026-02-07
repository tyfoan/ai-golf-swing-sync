//
//  NoEventDominanceRule.swift
//  golf-sync-swing
//
//  Validates that most frames in the window are classified as noEvent.
//  Real swings are brief — the window should be mostly "nothing happening".
//

import Foundation

struct NoEventDominanceRule: SwingValidationRule {

    var name: String { "noevent-dominance" }
    let minDominantFrames: Int

    init(minDominantFrames: Int = 24) {
        self.minDominantFrames = minDominantFrames
    }

    func validate(_ analysis: SwingNetAnalysis) -> ValidationResult {
        if analysis.noEventDominantFrameCount < minDominantFrames {
            return .fail(reason: "too few noEvent frames (\(analysis.noEventDominantFrameCount)/64, need \(minDominantFrames))")
        }
        return .pass
    }
}
