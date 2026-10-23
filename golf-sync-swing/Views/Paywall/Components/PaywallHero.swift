//
//  PaywallHero.swift
//  golf-sync-swing
//
//  Top section of the custom paywall: gold pre-headline, the source's pitch
//  (a three-line headline and a subheadline), and a phone-frame mockup
//  reused from onboarding for visual continuity.
//

import SwiftUI

struct PaywallHero: View {

    let source: PaywallSource

    @State private var visible = false

    private var pitch: PaywallPitch { .of(source) }

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
        Text(pitch.headline)
            .font(.title.weight(.heavy))
            .foregroundStyle(.white)
            .tracking(-0.6)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var subheadline: some View {
        Text(pitch.subheadline)
            .font(.subheadline)
            .foregroundStyle(Color.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityHidden(true)
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1)) {
            visible = true
        }
    }
}
