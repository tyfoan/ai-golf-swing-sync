//
//  OnboardingView.swift
//  golf-sync-swing
//
//  Full-screen onboarding flow: 3 benefit pages → paywall →
//  camera permission. Dismisses into the main app on completion.
//
//  Flow: Welcome → Auto-Sync → Pro Benefits → Paywall → Camera Access → Main App
//

import SwiftUI

struct OnboardingView: View {

    let onComplete: () -> Void

    @State private var currentPage = 0
    @State private var contentBlur: CGFloat = 0
    @State private var sheet: OnboardingSheet?
    @State private var skipVisible = false

    private let pages = OnboardingFeature.pages

    var body: some View {
        ZStack {
            Color.onboardingDark.ignoresSafeArea()
            pageContent
            chrome
        }
        .fullScreenCover(item: $sheet) { sheet in
            switch sheet {
            case .paywall:
                AppPaywallView(
                    source: .onboarding,
                    onDismiss: { self.sheet = .cameraPermission }
                )
            case .cameraPermission:
                CameraPermissionPageView { finishOnboarding() }
            }
        }
        .onAppear {
            Analytics.shared.track(.onboardingStarted)
            revealSkipAfterDelay()
        }
    }

    private enum OnboardingSheet: Identifiable {
        case paywall, cameraPermission
        var id: Self { self }
    }

    private func revealSkipAfterDelay() {
        guard !skipVisible else { return }
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.3)) { skipVisible = true }
            }
        }
    }

    // MARK: - Pages

    /// The cross-fading layer. Blurring on the way out and back in is what
    /// makes one page dissolve into the next instead of sliding.
    private var pageContent: some View {
        OnboardingPageView(
            feature: pages[currentPage],
            pageCount: pages.count,
            currentPage: currentPage
        )
        .id(currentPage)
        .transition(.opacity)
        .blur(radius: contentBlur)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .gesture(swipe)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: Metrics.swipeMinimum)
            .onEnded { drag in
                guard abs(drag.translation.width) > Metrics.swipeThreshold else { return }
                go(to: currentPage + (drag.translation.width < 0 ? 1 : -1))
            }
    }

    // MARK: - Chrome

    /// Top bar and CTA sit above the blurred layer, so they stay sharp while
    /// the page behind them dissolves.
    private var chrome: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(
                canGoBack: currentPage > 0,
                skipVisible: skipVisible,
                onBack: { go(to: currentPage - 1) },
                onSkip: skipAll
            )
            Spacer()
            OnboardingPrimaryButton(title: pages[currentPage].ctaTitle, action: advancePage)
                .padding(.horizontal, Metrics.ctaHorizontalPadding)
                .padding(.bottom, Metrics.ctaBottomPadding)
        }
    }

    // MARK: - Navigation

    private var isLastPage: Bool {
        currentPage == pages.count - 1
    }

    private func advancePage() {
        guard !isLastPage else {
            sheet = .paywall
            return
        }
        go(to: currentPage + 1)
    }

    /// Blur out, swap the page underneath the blur, then sharpen back up.
    private func go(to page: Int) {
        guard pages.indices.contains(page), page != currentPage else { return }
        withAnimation(.easeIn(duration: Metrics.blurOut)) { contentBlur = Metrics.blurRadius }
        withAnimation(.easeInOut(duration: Metrics.crossFade)) { currentPage = page }
        withAnimation(.easeOut(duration: Metrics.blurIn).delay(Metrics.blurOut)) { contentBlur = 0 }
    }

    /// Skip goes directly to paywall (skipping remaining onboarding pages).
    private func skipAll() {
        sheet = .paywall
    }

    private func finishOnboarding() {
        sheet = nil
        OnboardingService.shared.completeOnboarding()
        Analytics.shared.track(.onboardingCompleted)
        onComplete()
    }

    // MARK: - Metrics

    private enum Metrics {
        static let blurRadius: CGFloat = 18
        static let blurOut: TimeInterval = 0.16
        static let blurIn: TimeInterval = 0.30
        static let crossFade: TimeInterval = 0.34
        static let swipeMinimum: CGFloat = 24
        static let swipeThreshold: CGFloat = 60
        static let ctaHorizontalPadding: CGFloat = 28
        static let ctaBottomPadding: CGFloat = 34
    }
}
