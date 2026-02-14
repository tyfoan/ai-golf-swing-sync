//
//  FeatureAccess.swift
//  golf-sync-swing
//
//  Single source of truth for premium feature gating.
//  Delegates to PurchaseService for RevenueCat entitlement checks.
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
    static func isUnlocked(_ feature: PremiumFeature) -> Bool {
        PurchaseService.shared.isPremium
    }

    static var isPremiumUser: Bool {
        PurchaseService.shared.isPremium
    }
}
