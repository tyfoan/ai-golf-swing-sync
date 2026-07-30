//
//  OnboardingPageIndicator.swift
//  golf-sync-swing
//
//  Page dots where the active page is an elongated pill. Sits above the
//  title, over the fading edge of the hero artwork.
//

import SwiftUI

struct OnboardingPageIndicator: View {

    let pageCount: Int
    let currentPage: Int

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            ForEach(0 ..< pageCount, id: \.self) { index in
                Capsule()
                    .fill(fill(for: index))
                    .frame(width: width(for: index), height: Metrics.height)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: currentPage)
    }

    private func fill(for index: Int) -> Color {
        index == currentPage ? .white : Color.white.opacity(0.32)
    }

    private func width(for index: Int) -> CGFloat {
        index == currentPage ? Metrics.activeWidth : Metrics.height
    }

    private enum Metrics {
        static let spacing: CGFloat = 6
        static let height: CGFloat = 6
        static let activeWidth: CGFloat = 22
    }
}
