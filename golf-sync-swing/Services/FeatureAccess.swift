//
//  FeatureAccess.swift
//  golf-sync-swing
//
//  Single source of truth for premium feature gating.
//  All features unlocked until paywall is implemented.
//

import Foundation

enum PremiumFeature: String, CaseIterable {
    case synchronizedPlayback
    case onionSkinMode
    case overlayMode
    case poseEstimation
    case exportHD
    case exportNoWatermark
}

struct FeatureAccess {
    static func isUnlocked(_ feature: PremiumFeature) -> Bool { true }

    static var isPremiumUser: Bool { true }
}
