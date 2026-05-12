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
    case topBottom  = "Top / Bottom"
    case stacked    = "Stacked"
    case sequential = "Sequential"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sideBySide: return String(localized: "Side-by-Side", comment: "Comparison mode: two videos side by side")
        case .topBottom:  return String(localized: "Top / Bottom", comment: "Comparison mode: one video stacked above the other")
        case .stacked:    return String(localized: "Stacked", comment: "Comparison mode: videos overlaid with opacity blend")
        case .sequential: return String(localized: "Sequential", comment: "Comparison mode: videos play one after the other")
        }
    }

    var iconName: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .topBottom:  return "rectangle.split.1x2"
        case .stacked:    return "square.on.square"
        case .sequential: return "arrow.right.to.line"
        }
    }

    var premiumFeature: PremiumFeature? {
        switch self {
        case .sideBySide, .topBottom: return nil
        case .stacked, .sequential:   return .advancedComparisonModes
        }
    }

    var isAvailable: Bool {
        guard let feature = premiumFeature else { return true }
        return FeatureAccess.isUnlocked(feature)
    }

    /// Whether the sync-offset adjustment strip should be visible.
    /// Side-by-side and top-bottom expose manual sync drift; stacked is locked to its
    /// computed offset and sequential has no concept of concurrent drift.
    var showsSyncOffsetStrip: Bool {
        switch self {
        case .sideBySide, .topBottom: return true
        case .stacked, .sequential:   return false
        }
    }

    /// Whether the opacity slider control should be visible.
    /// Only stacked has a user-tunable opacity blend.
    var showsOpacitySlider: Bool {
        switch self {
        case .stacked:                              return true
        case .sideBySide, .topBottom, .sequential:  return false
        }
    }

    /// The default export aspect ratio when entering the export editor for this mode.
    /// SideBySide → 16:9 HSTACK; topBottom → 9:16 VSTACK; the others fill a portrait canvas.
    var defaultExportAspect: ExportAspectRatio {
        switch self {
        case .sideBySide: return .sideBySide
        case .topBottom, .stacked, .sequential: return .tikTokVertical
        }
    }

    /// Whether the editor should expose a "Swing 1 / Swing 2" picker.
    /// Only sequential mode edits one swing at a time.
    var showsSequentialPicker: Bool {
        switch self {
        case .sequential:                          return true
        case .sideBySide, .topBottom, .stacked:    return false
        }
    }
}
