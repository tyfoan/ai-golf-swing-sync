//
//  ComparisonMode.swift
//  golf-sync-swing
//
//  Display modes for comparison playback. All modes sync at impact —
//  sync is no longer a separate mode.
//

import Foundation

enum ComparisonMode: String, CaseIterable, Identifiable {
    case sideBySide = "Side-by-Side"
    case stacked    = "Stacked"
    case sequential = "Sequential"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .stacked:    return "square.on.square"
        case .sequential: return "arrow.right.to.line"
        }
    }

    var premiumFeature: PremiumFeature? {
        switch self {
        case .sideBySide: return nil
        case .stacked, .sequential: return .advancedComparisonModes
        }
    }

    var isAvailable: Bool {
        guard let feature = premiumFeature else { return true }
        return FeatureAccess.isUnlocked(feature)
    }
}
