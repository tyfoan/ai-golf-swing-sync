//
//  PaywallSource.swift
//  golf-sync-swing
//
//  Identifies where a paywall was triggered for analytics.
//

import Foundation

enum PaywallSource: String {
    case onboarding
    case featureGate
    case settings
}
