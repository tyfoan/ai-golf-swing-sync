//
//  OnboardingHeroStage.swift
//  golf-sync-swing
//
//  Full-bleed hero stage for one onboarding page. A bright backdrop bleeds to
//  every screen edge and dissolves into the page background through a bottom
//  scrim, so the title block can sit *over* the artwork rather than below it.
//

import SwiftUI

struct OnboardingHeroStage<Content: View>: View {

    /// Space the caption block occupies at the bottom. The mockup centres in
    /// whatever is left, so there is no dead gap between artwork and text.
    private let bottomReserve: CGFloat
    private let content: () -> Content

    init(bottomReserve: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.bottomReserve = bottomReserve
        self.content = content
    }

    var body: some View {
        ZStack {
            backdrop
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, Metrics.contentInset)
                .padding(.bottom, bottomReserve)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { scrim }
        .clipped()
    }

    // MARK: - Backdrop

    /// Flowing mesh, brightest just behind the mockup — reads as wallpaper
    /// rather than a flat fill.
    private var backdrop: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.45], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                .onboardingHeroDeep, .onboardingHeroGlow, .onboardingHeroDeep,
                .onboardingHeroGlow, .onboardingHeroLift, .onboardingHeroGlow,
                .onboardingHeroDeep, .onboardingHeroGlow, .onboardingHeroDeep
            ]
        )
    }

    // MARK: - Scrim

    /// Transparent across the artwork, opaque by the time it reaches the
    /// title block. The long ramp is what makes the image *dissolve* into the
    /// background instead of ending on a visible edge.
    private var scrim: some View {
        LinearGradient(stops: Metrics.scrimStops, startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
    }
}

// Outside the generic type: Swift does not allow static stored properties
// on a nested type of a generic.
private enum Metrics {

    static let contentInset: CGFloat = 72

    /// Stays translucent well past the title so the artwork still reads
    /// behind it — a scrim, not a cut-off.
    static let scrimStops: [Gradient.Stop] = [
        .init(color: .clear, location: 0.00),
        .init(color: Color.onboardingDark.opacity(0.08), location: 0.44),
        .init(color: Color.onboardingDark.opacity(0.38), location: 0.62),
        .init(color: Color.onboardingDark.opacity(0.72), location: 0.76),
        .init(color: Color.onboardingDark.opacity(0.93), location: 0.88),
        .init(color: Color.onboardingDark, location: 0.97)
    ]
}
