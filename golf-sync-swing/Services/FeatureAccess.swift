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
    // TODO: Gate pose estimation behind premium when real-time skeleton overlay ships
    case poseEstimation
    case exportHD
    case exportNoWatermark
}

struct FeatureAccess {
    static func isUnlocked(_ feature: PremiumFeature) -> Bool {
        #if DEBUG
        if ScreenshotModeService.shared.isEnabled { return true }
        #endif
        return PurchaseService.shared.isPremium
    }

    static var isPremiumUser: Bool {
        #if DEBUG
        if ScreenshotModeService.shared.isEnabled { return true }
        #endif
        return PurchaseService.shared.isPremium
    }
}
