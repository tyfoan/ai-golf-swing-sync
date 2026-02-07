//
//  ImpactDetectionChain.swift
//  golf-sync-swing
//
//  Chain of responsibility for impact detection.
//  Strategies are tried in priority order; first non-nil result wins.
//

import Foundation

struct ImpactDetectionChain {

    private let strategies: [ImpactDetectionStrategy]

    init(strategies: [ImpactDetectionStrategy]) {
        self.strategies = strategies
    }

    static func `default`() -> ImpactDetectionChain {
        ImpactDetectionChain(strategies: [
            DownswingToFollowThroughStrategy(),
            BackswingToFollowThroughStrategy(),
            DownswingDecayStrategy(),
            BackswingDecayStrategy(),
        ])
    }

    func detect(in history: [PredictionRecord]) -> ImpactCandidate? {
        for strategy in strategies {
            if let candidate = strategy.detectImpact(in: history) {
                return candidate
            }
        }
        return nil
    }
}
