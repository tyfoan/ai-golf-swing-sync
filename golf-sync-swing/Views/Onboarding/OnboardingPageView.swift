//
//  OnboardingPageView.swift
//  golf-sync-swing
//
//  A single onboarding page: full-bleed hero artwork with the page indicator
//  and centred title block sitting over its fading lower edge. The whole page
//  is what cross-fades between steps — the CTA and top bar live above it and
//  stay crisp.
//

import SwiftUI

struct OnboardingPageView: View {

    let feature: OnboardingFeature
    let pageCount: Int
    let currentPage: Int

    @State private var visible = false

    var body: some View {
        ZStack(alignment: .bottom) {
            hero
            caption
        }
        .onAppear { animateIn() }
    }

    private var hero: some View {
        OnboardingHeroStage(bottomReserve: Metrics.heroBottomReserve) {
            PhoneFrameView { feature.heroBuilder() }
                .opacity(visible ? 1 : 0)
                .scaleEffect(visible ? 1 : 0.94)
        }
    }

    private var caption: some View {
        VStack(spacing: Metrics.captionSpacing) {
            OnboardingPageIndicator(pageCount: pageCount, currentPage: currentPage)
            OnboardingTitleBlock(title: feature.title, subtitle: feature.subtitle)
        }
        .padding(.bottom, Metrics.captionBottomInset)
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.05)) {
            visible = true
        }
    }

    private enum Metrics {
        static let captionSpacing: CGFloat = 18
        /// Clears the CTA that OnboardingView pins below this page.
        static let captionBottomInset: CGFloat = 150
        /// captionBottomInset plus the caption's own height, so the hero
        /// centres its mockup in the space actually left over.
        static let heroBottomReserve: CGFloat = 256
    }
}
