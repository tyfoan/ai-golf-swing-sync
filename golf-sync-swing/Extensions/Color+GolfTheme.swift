//
//  Color+GolfTheme.swift
//  golf-sync-swing
//
//  Fairway design theme — premium golf club aesthetic.
//

import SwiftUI

extension Color {
    // MARK: - Primary Greens

    static let fairwayGreen = Color(red: 0.176, green: 0.416, blue: 0.31)
    static let pineGreen    = Color(red: 0.106, green: 0.263, blue: 0.196)
    static let mintMist     = Color(red: 0.847, green: 0.953, blue: 0.863)

    // MARK: - Warm Accents

    static let sand         = Color(red: 0.831, green: 0.639, blue: 0.451)
    static let sandLight    = Color(red: 0.996, green: 0.98, blue: 0.878)
    static let ivory        = Color(red: 0.992, green: 0.988, blue: 0.98)

    // MARK: - Semantic

    static let charcoal     = Color(red: 0.169, green: 0.176, blue: 0.169)
    static let flagRed      = Color(red: 0.757, green: 0.161, blue: 0.18)

    // MARK: - Onboarding & Paywall

    // Dark backgrounds
    static let onboardingDark      = Color(red: 0.055, green: 0.078, blue: 0.067)
    static let onboardingDeepGreen = Color(red: 0.047, green: 0.145, blue: 0.102)
    static let onboardingMidGreen  = Color(red: 0.098, green: 0.224, blue: 0.165)
    static let onboardingRichGreen = Color(red: 0.133, green: 0.322, blue: 0.239)

    // Gold accents
    static let onboardingGold      = Color(red: 0.871, green: 0.737, blue: 0.459)
    static let onboardingGoldLight = Color(red: 0.953, green: 0.878, blue: 0.698)
    static let onboardingGoldDim   = Color(red: 0.569, green: 0.467, blue: 0.278)

    // Feature icon tints (per page)
    static let onboardingTealAccent  = Color(red: 0.318, green: 0.745, blue: 0.604)
    static let onboardingAmberAccent = Color(red: 0.918, green: 0.702, blue: 0.341)
    static let onboardingCrownGold   = Color(red: 0.953, green: 0.812, blue: 0.459)

    // MARK: - Backward Compatibility

    static let appTeal = fairwayGreen
}
