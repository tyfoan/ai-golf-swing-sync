//
//  ImpactDetectionStrategy.swift
//  golf-sync-swing
//
//  Protocol for polymorphic impact detection strategies.
//  Each strategy looks for a specific pattern in prediction history
//  that indicates a golf swing impact has occurred.
//

import Foundation

struct ImpactCandidate {
    let swingBounds: SwingBounds
    let strategy: String
}

protocol ImpactDetectionStrategy {
    var name: String { get }
    func detectImpact(in history: [PredictionRecord]) -> ImpactCandidate?
}
