//
//  OnboardingPageView.swift
//  golf-sync-swing
//
//  A single onboarding page displaying a feature's icon,
//  title, subtitle, and highlight list. Designed for
//  full-screen presentation within a TabView.
//

import SwiftUI

struct OnboardingPageView: View {

    let feature: OnboardingFeature

    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var highlightsVisible = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            heroIcon
            titleSection
            highlightList
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear { animateIn() }
    }

    // MARK: - Hero Icon

    private var heroIcon: some View {
        ZStack {
            Circle()
                .fill(feature.iconColor.opacity(0.15))
                .frame(width: 120, height: 120)

            Image(systemName: feature.iconName)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(feature.iconColor)
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(spacing: 12) {
            Text(feature.title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(feature.subtitle)
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
    }

    // MARK: - Highlights

    private var highlightList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(feature.highlights.enumerated()), id: \.element.id) { index, highlight in
                highlightRow(highlight, index: index)
            }
        }
        .padding(.horizontal, 8)
    }

    private func highlightRow(_ highlight: OnboardingFeature.Highlight, index: Int) -> some View {
        HStack(spacing: 16) {
            Image(systemName: highlight.icon)
                .font(.title3)
                .foregroundStyle(feature.iconColor)
                .frame(width: 32)

            Text(highlight.text)
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .opacity(highlightsVisible ? 1 : 0)
        .offset(y: highlightsVisible ? 0 : 20)
        .animation(
            .easeOut(duration: 0.4).delay(Double(index) * 0.15 + 0.3),
            value: highlightsVisible
        )
    }

    // MARK: - Animation

    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            iconScale = 1.0
            iconOpacity = 1.0
        }
        highlightsVisible = true
    }
}
