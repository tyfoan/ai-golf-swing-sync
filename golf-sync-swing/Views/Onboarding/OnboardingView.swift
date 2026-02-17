//
//  OnboardingView.swift
//  golf-sync-swing
//
//  Full-screen onboarding flow: 3 benefit pages followed by
//  a paywall. Dismisses into the main app on completion.
//
//  Flow: Welcome → Auto-Sync → Pro Benefits → Paywall → Main App
//

import SwiftUI

struct OnboardingView: View {

    let onComplete: () -> Void

    @State private var currentPage = 0
    @State private var showPaywall = false

    private let pages = OnboardingFeature.pages

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                skipButton
                pageContent
                pageIndicator
                actionButton
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            AppPaywallView(
                source: .onboarding,
                onDismiss: { finishOnboarding() }
            )
        }
    }

    // MARK: - Skip

    private var skipButton: some View {
        HStack {
            Spacer()
            Button("Skip") { finishOnboarding() }
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.trailing, 24)
                .padding(.top, 12)
        }
    }

    // MARK: - Background

    private var background: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                .onboardingDark,      .onboardingDeepGreen, .onboardingDark,
                .onboardingDeepGreen, .onboardingMidGreen,  .onboardingDeepGreen,
                .onboardingDark,      .onboardingDeepGreen, .onboardingDark
            ]
        )
        .ignoresSafeArea()
    }

    // MARK: - Pages

    private var pageContent: some View {
        TabView(selection: $currentPage) {
            ForEach(pages) { page in
                OnboardingPageView(feature: page)
                    .tag(page.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.3), value: currentPage)
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages) { page in
                Capsule()
                    .fill(page.id == currentPage ? Color.onboardingGold : Color.white.opacity(0.2))
                    .frame(width: page.id == currentPage ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: currentPage)
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button(action: advancePage) {
            Text(buttonTitle)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.onboardingRichGreen, Color.fairwayGreen],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .shadow(color: Color.fairwayGreen.opacity(0.4), radius: 12, y: 4)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 48)
    }

    private var buttonTitle: String {
        isLastPage ? "Get Started" : "Continue"
    }

    // MARK: - Navigation

    private var isLastPage: Bool {
        currentPage == pages.count - 1
    }

    private func advancePage() {
        guard !isLastPage else {
            showPaywall = true
            return
        }
        withAnimation {
            currentPage += 1
        }
    }

    private func finishOnboarding() {
        OnboardingService.shared.completeOnboarding()
        onComplete()
    }
}
