//
//  FeatureAccess.swift
//  golf-sync-swing
//
//  Single source of truth for premium feature gating.
//  Delegates to PurchaseService for RevenueCat entitlement checks.
//

import Foundation

enum PremiumFeature: String, CaseIterable {
    case advancedComparisonModes
    case poseEstimation
    case exportHD
    case exportNoWatermark
    case proSwingLibrary
    case unlimitedLibrary
}

struct FeatureAccess {
    static func isUnlocked(_ feature: PremiumFeature) -> Bool {
        #if DEBUG
        if devPremiumOverride { return true }
        if ScreenshotModeService.shared.isEnabled { return true }
        #endif
        return PurchaseService.shared.isPremium
    }

    static var isPremiumUser: Bool {
        #if DEBUG
        if devPremiumOverride { return true }
        if ScreenshotModeService.shared.isEnabled { return true }
        #endif
        return PurchaseService.shared.isPremium
    }

    #if DEBUG
    static let devPremiumOverrideKey = "dev.premiumOverride"

    private static var devPremiumOverride: Bool {
        UserDefaults.standard.bool(forKey: devPremiumOverrideKey)
    }
    #endif
}
