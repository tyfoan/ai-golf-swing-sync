//
//  FeatureAccess.swift
//  golf-sync-swing
//
//  Single source of truth for premium feature gating.
//  In DEBUG builds all features are unlocked for development.
//  In RELEASE builds features require a subscription (future paywall).
//

import Foundation

enum PremiumFeature: String, CaseIterable {
    case onionSkinMode
    case overlayMode
    case poseEstimation
    case tempoSync
    case exportHD
    case exportNoWatermark
}

struct FeatureAccess {
    static func isUnlocked(_ feature: PremiumFeature) -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var isPremiumUser: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
