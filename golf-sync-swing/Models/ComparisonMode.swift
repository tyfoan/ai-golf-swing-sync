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

    /// Whether the sync-offset adjustment strip should be visible.
    /// Only sideBySide exposes manual sync drift; stacked is locked to its
    /// computed offset and sequential has no concept of concurrent drift.
    var showsSyncOffsetStrip: Bool {
        switch self {
        case .sideBySide:           return true
        case .stacked, .sequential: return false
        }
    }

    /// Whether the opacity slider control should be visible.
    /// Only stacked has a user-tunable opacity blend.
    var showsOpacitySlider: Bool {
        switch self {
        case .stacked:                  return true
        case .sideBySide, .sequential:  return false
        }
    }
}
