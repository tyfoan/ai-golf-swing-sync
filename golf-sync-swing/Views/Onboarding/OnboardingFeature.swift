//
//  OnboardingFeature.swift
//  golf-sync-swing
//
//  Data model for a single onboarding page. Each page is a killer-first
//  product showcase with a hero animation, bold headline, and CTA copy.
//

import SwiftUI

struct OnboardingFeature: Identifiable {

    let id: Int
    let preHeadline: String
    let headlineLines: [String]
    let subtitle: String
    let ctaTitle: String
    let heroBuilder: () -> AnyView
}

// MARK: - Pages

extension OnboardingFeature {

    static let pages: [OnboardingFeature] = [killer, camera, tools]

    static let killer = OnboardingFeature(
        id: 0,
        preHeadline: String(localized: "BUILT FOR SERIOUS GOLFERS", comment: "Onboarding page 1 eyebrow (small uppercase line above headline)"),
        headlineLines: [
            String(localized: "Your swing", comment: "Onboarding page 1 headline, line 1 of 3"),
            String(localized: "vs a pro's.", comment: "Onboarding page 1 headline, line 2 of 3"),
            String(localized: "Auto-synced.", comment: "Onboarding page 1 headline, line 3 of 3")
        ],
        subtitle: String(localized: "AI lines you up frame by frame at the moment of impact.", comment: "Onboarding page 1 subtitle under the headline"),
        ctaTitle: String(localized: "Continue", comment: "Onboarding primary button (advances to next page)"),
        heroBuilder: { AnyView(KillerSyncMockup()) }
    )

    static let camera = OnboardingFeature(
        id: 1,
        preHeadline: String(localized: "ZERO-TAP CAPTURE", comment: "Onboarding page 2 eyebrow"),
        headlineLines: [
            String(localized: "Just point.", comment: "Onboarding page 2 headline, line 1 of 3"),
            String(localized: "It knows when", comment: "Onboarding page 2 headline, line 2 of 3"),
            String(localized: "you swing.", comment: "Onboarding page 2 headline, line 3 of 3")
        ],
        subtitle: String(localized: "Detects, trims, and saves every swing automatically.", comment: "Onboarding page 2 subtitle"),
        ctaTitle: String(localized: "Continue", comment: "Onboarding primary button (advances to next page)"),
        heroBuilder: { AnyView(SmartCameraMockup()) }
    )

    static let tools = OnboardingFeature(
        id: 2,
        preHeadline: String(localized: "FRAME BY FRAME", comment: "Onboarding page 3 eyebrow"),
        headlineLines: [
            String(localized: "Spot the fix.", comment: "Onboarding page 3 headline, line 1 of 3"),
            String(localized: "Send it to", comment: "Onboarding page 3 headline, line 2 of 3"),
            String(localized: "your coach.", comment: "Onboarding page 3 headline, line 3 of 3")
        ],
        subtitle: String(localized: "8× slow-mo, pro library, HD export.", comment: "Onboarding page 3 subtitle"),
        ctaTitle: String(localized: "Get Started", comment: "Onboarding final-page button that dismisses onboarding"),
        heroBuilder: { AnyView(SlowMoToolsMockup()) }
    )
}
