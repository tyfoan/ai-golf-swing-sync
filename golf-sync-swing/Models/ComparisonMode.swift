//
//  ComparisonMode.swift
//  golf-sync-swing
//
//  Display modes for side-by-side comparison.
//

import Foundation

enum ComparisonMode: String, CaseIterable, Identifiable {
    case sideBySide  = "Side-By-Side"
    case onionSkin   = "Onion Skin"
    case overlay     = "Overlay"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .onionSkin:  return "square.on.square"
        case .overlay:    return "rectangle.on.rectangle"
        }
    }

    var requiresPremium: Bool {
        switch self {
        case .sideBySide: return false
        case .onionSkin:  return true
        case .overlay:    return true
        }
    }

    var premiumFeature: PremiumFeature? {
        switch self {
        case .sideBySide: return nil
        case .onionSkin:  return .onionSkinMode
        case .overlay:    return .overlayMode
        }
    }

    var isAvailable: Bool {
        guard let feature = premiumFeature else { return true }
        return FeatureAccess.isUnlocked(feature)
    }
}
