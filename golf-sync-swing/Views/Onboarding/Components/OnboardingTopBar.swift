//
//  OnboardingTopBar.swift
//  golf-sync-swing
//
//  Back chevron on the left, Skip on the right — the ‹ / ✓ arrangement from
//  the macOS welcome panel. Both fade rather than appear, so the bar never
//  pops during a page change.
//

import SwiftUI

struct OnboardingTopBar: View {

    let canGoBack: Bool
    let skipVisible: Bool
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack {
            backButton
            Spacer()
            skipButton
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.top, Metrics.topPadding)
    }

    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: Metrics.tapTarget, height: Metrics.tapTarget, alignment: .leading)
        }
        .opacity(canGoBack ? 1 : 0)
        .disabled(!canGoBack)
        .animation(.easeInOut(duration: 0.25), value: canGoBack)
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            Text("Skip", comment: "Onboarding button that jumps straight to the paywall")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(height: Metrics.tapTarget, alignment: .trailing)
        }
        .opacity(skipVisible ? 1 : 0)
        .disabled(!skipVisible)
        .animation(.easeIn(duration: 0.3), value: skipVisible)
    }

    private enum Metrics {
        static let horizontalPadding: CGFloat = 20
        static let topPadding: CGFloat = 8
        static let tapTarget: CGFloat = 44
    }
}
