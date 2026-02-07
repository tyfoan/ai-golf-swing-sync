//
//  TemporalOrderRule.swift
//  golf-sync-swing
//
//  Validates that swing events appear in correct temporal order:
//  address < top < impact.
//

import Foundation

struct TemporalOrderRule: SwingValidationRule {

    var name: String { "temporal-order" }

    func validate(_ analysis: SwingNetAnalysis) -> ValidationResult {
        let addressFrame = analysis.eventPeaks[.address]?.frame ?? 0
        let topFrame = analysis.eventPeaks[.top]?.frame ?? 0
        let impactFrame = analysis.impactFrame

        if !(addressFrame < topFrame && topFrame < impactFrame) {
            return .fail(reason: "temporal order violated: address=\(addressFrame) top=\(topFrame) impact=\(impactFrame)")
        }
        return .pass
    }
}
