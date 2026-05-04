//
//  OnboardingPageView.swift
//  golf-sync-swing
//
//  A single onboarding page: pre-headline label, three-line bold
//  headline, subtitle, and a phone-frame hero mockup. Designed for
//  full-screen presentation within a TabView.
//

import SwiftUI

struct OnboardingPageView: View {

    let feature: OnboardingFeature

    @State private var visible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            preHeadline
            headline
            subtitle
            heroSection
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .onAppear { animateIn() }
    }

    private var preHeadline: some View {
        Text(feature.preHeadline)
            .font(.caption2.weight(.bold))
            .tracking(2)
            .foregroundStyle(Color.onboardingGold)
            .padding(.top, 8)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(feature.headlineLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(.white)
                    .tracking(-0.6)
            }
        }
    }

    private var subtitle: some View {
        Text(feature.subtitle)
            .font(.subheadline)
            .foregroundStyle(Color.white.opacity(0.7))
            .lineLimit(2)
    }

    private var heroSection: some View {
        HStack {
            Spacer()
            PhoneFrameView { feature.heroBuilder() }
                .opacity(visible ? 1 : 0)
                .scaleEffect(visible ? 1 : 0.92)
            Spacer()
        }
        .padding(.top, 8)
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1)) {
            visible = true
        }
    }
}
