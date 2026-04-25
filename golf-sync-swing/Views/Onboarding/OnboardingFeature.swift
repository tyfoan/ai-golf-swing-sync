//
//  OnboardingFeature.swift
//  golf-sync-swing
//
//  Data model for a single onboarding page.
//  Each page showcases a benefit the user gains from the app.
//

import SwiftUI

struct OnboardingFeature: Identifiable {

    let id: Int
    let title: String
    let subtitle: String
    let iconName: String
    let iconColor: Color
    let highlights: [Highlight]

    struct Highlight: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
    }
}

// MARK: - Pages

extension OnboardingFeature {

    static let pages: [OnboardingFeature] = [welcome, autoSync, proBenefits]

    static let welcome = OnboardingFeature(
        id: 0,
        title: "AI-Powered Swing Analysis",
        subtitle: "Your personal AI golf coach in your pocket",
        iconName: "brain",
        iconColor: .onboardingTealAccent,
        highlights: [
            Highlight(icon: "wand.and.stars", text: "AI detects your swing phases automatically"),
            Highlight(icon: "arrow.triangle.2.circlepath", text: "Smart sync aligns swings at the point of impact"),
            Highlight(icon: "iphone", text: "On-device AI — no internet needed"),
        ]
    )

    static let autoSync = OnboardingFeature(
        id: 1,
        title: "AI Sync at Impact",
        subtitle: "Intelligent analysis, frame by frame",
        iconName: "cpu",
        iconColor: .onboardingAmberAccent,
        highlights: [
            Highlight(icon: "bolt.fill", text: "AI identifies backswing, downswing, and follow-through"),
            Highlight(icon: "clock.arrow.2.circlepath", text: "Automatic alignment at the moment of impact"),
            Highlight(icon: "gauge.with.dots.needle.33percent", text: "Up to 8x slow-motion for detailed analysis"),
        ]
    )

    static let proBenefits = OnboardingFeature(
        id: 2,
        title: "Unlock AI Pro Tools",
        subtitle: "Take your analysis to the next level",
        iconName: "crown.fill",
        iconColor: .onboardingCrownGold,
        highlights: [
            Highlight(icon: "arrow.triangle.2.circlepath", text: "AI-synchronized side-by-side playback"),
            Highlight(icon: "square.on.square", text: "Onion skin and overlay comparison modes"),
            Highlight(icon: "square.and.arrow.up", text: "HD export with no watermark"),
        ]
    )
}
