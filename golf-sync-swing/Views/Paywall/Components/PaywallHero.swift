//
//  PaywallHero.swift
//  golf-sync-swing
//
//  Top section of the custom paywall: gold pre-headline, three-line bold
//  headline (varies by source), subheadline, and a phone-frame mockup
//  reused from onboarding for visual continuity.
//

import SwiftUI

struct PaywallHero: View {

    let source: PaywallSource

    @State private var visible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preHeadline
            headline
            subheadline
            mockup
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { animateIn() }
    }

    private var preHeadline: some View {
        Text("GOLF SYNC PRO")
            .font(.caption2.weight(.bold))
            .tracking(2)
            .foregroundStyle(Color.onboardingGold)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(headlineLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.white)
                    .tracking(-0.6)
            }
        }
    }

    private var subheadline: some View {
        Text(subheadlineText)
            .font(.subheadline)
            .foregroundStyle(Color.white.opacity(0.7))
            .lineLimit(2)
    }

    private var mockup: some View {
        HStack {
            Spacer()
            PhoneFrameView { AnyView(KillerSyncMockup()) }
                .opacity(visible ? 1 : 0)
                .scaleEffect(visible ? 1 : 0.92)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var headlineLines: [LocalizedStringKey] {
        switch source {
        case .onboarding:
            return ["Your swing", "vs a pro's.", "Frame-locked."]
        case .featureGate:
            return ["Unlock", "the full", "comparison."]
        case .settings:
            return ["Go Pro.", "Every feature.", "Forever."]
        }
    }

    private var subheadlineText: LocalizedStringKey {
        switch source {
        case .onboarding:
            return "AI lines you up frame by frame at the moment of impact."
        case .featureGate:
            return "Side-by-side, onion-skin, overlay — and HD export."
        case .settings:
            return "Unlock every comparison mode and pro tool."
        }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1)) {
            visible = true
        }
    }
}
