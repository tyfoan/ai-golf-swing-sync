//
//  OnboardingTitleBlock.swift
//  golf-sync-swing
//
//  Centred title and two-line subtitle. Both carry a soft dark shadow so they
//  stay legible where they overlap the hero artwork.
//

import SwiftUI

struct OnboardingTitleBlock: View {

    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Metrics.titleGap) {
            headline
            caption
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Metrics.horizontalPadding)
    }

    private var headline: some View {
        Text(title)
            .font(.system(size: Metrics.titleSize, weight: .bold))
            .tracking(Metrics.titleTracking)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
    }

    /// Width-constrained rather than pre-split, so every language wraps at
    /// its own natural point instead of an English one.
    private var caption: some View {
        Text(subtitle)
            .font(.system(size: Metrics.subtitleSize))
            .foregroundStyle(Color.white.opacity(0.68))
            .lineSpacing(Metrics.subtitleLineSpacing)
            .frame(maxWidth: Metrics.subtitleMaxWidth)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
    }

    private enum Metrics {
        static let titleSize: CGFloat = 28
        static let titleTracking: CGFloat = -0.4
        static let titleGap: CGFloat = 8
        static let subtitleSize: CGFloat = 15
        static let subtitleLineSpacing: CGFloat = 3
        static let subtitleMaxWidth: CGFloat = 290
        static let horizontalPadding: CGFloat = 32
    }
}
