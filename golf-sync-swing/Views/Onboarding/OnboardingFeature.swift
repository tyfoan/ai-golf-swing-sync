//
//  OnboardingFeature.swift
//  golf-sync-swing
//
//  Data model for a single onboarding page: a hero mockup, one centred
//  title, a two-line subtitle, and the CTA copy for that step.
//

import SwiftUI

struct OnboardingFeature: Identifiable {

    let id: Int
    let title: String
    /// One whole sentence, wrapped by the layout. Never pre-split into lines:
    /// word order differs by language, so half-sentences cannot be translated.
    let subtitle: String
    let ctaTitle: String
    let heroBuilder: () -> AnyView
}

// MARK: - Pages

extension OnboardingFeature {

    static let pages: [OnboardingFeature] = [killer, camera, tools]

    static let killer = OnboardingFeature(
        id: 0,
        title: String(localized: "Your Swing vs a Pro's", comment: "Onboarding page 1 title"),
        subtitle: String(localized: "AI lines you up frame by frame at the moment of impact.", comment: "Onboarding page 1 subtitle under the headline"),
        ctaTitle: String(localized: "Continue", comment: "Onboarding primary button (advances to next page)"),
        heroBuilder: { AnyView(KillerSyncMockup()) }
    )

    static let camera = OnboardingFeature(
        id: 1,
        title: String(localized: "Zero-Tap Capture", comment: "Onboarding page 2 title"),
        subtitle: String(localized: "Detects, trims, and saves every swing automatically.", comment: "Onboarding page 2 subtitle"),
        ctaTitle: String(localized: "Continue", comment: "Onboarding primary button (advances to next page)"),
        heroBuilder: { AnyView(SmartCameraMockup()) }
    )

    static let tools = OnboardingFeature(
        id: 2,
        title: String(localized: "Share Your Best Swings", comment: "Onboarding page 3 title"),
        subtitle: String(localized: "Export a highlight reel or a side-by-side, in HD.", comment: "Onboarding page 3 subtitle"),
        ctaTitle: String(localized: "Get Started", comment: "Onboarding final-page button that dismisses onboarding"),
        heroBuilder: { AnyView(ExportShareMockup()) }
    )
}
