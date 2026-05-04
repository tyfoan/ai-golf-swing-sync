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
        preHeadline: "BUILT FOR SERIOUS GOLFERS",
        headlineLines: ["Your swing", "vs a pro's.", "Auto-synced."],
        subtitle: "AI lines you up frame by frame at the moment of impact.",
        ctaTitle: "Continue",
        heroBuilder: { AnyView(KillerSyncMockup()) }
    )

    static let camera = OnboardingFeature(
        id: 1,
        preHeadline: "ZERO-TAP CAPTURE",
        headlineLines: ["Just point.", "It knows when", "you swing."],
        subtitle: "Detects, trims, and saves every swing automatically.",
        ctaTitle: "Continue",
        heroBuilder: { AnyView(SmartCameraMockup()) }
    )

    static let tools = OnboardingFeature(
        id: 2,
        preHeadline: "FRAME BY FRAME",
        headlineLines: ["Spot the fix.", "Send it to", "your coach."],
        subtitle: "8× slow-mo, drawing tools, HD export.",
        ctaTitle: "Get Started",
        heroBuilder: { AnyView(SlowMoToolsMockup()) }
    )
}
