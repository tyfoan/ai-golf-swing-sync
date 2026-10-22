//
//  PaywallSource.swift
//  golf-sync-swing
//
//  Identifies where a paywall was triggered, for analytics and for the pitch it
//  shows. Onboarding has no paywall since 1.3.4, so it has no source either.
//

import Foundation

enum PaywallSource: String {
    case featureGate
    case settings
}
