//
//  KillerSyncMockup.swift
//  golf-sync-swing
//
//  Hero animation for onboarding screen 1: two videos slide into
//  sync at impact, gold IMPACT line glows between them.
//

import SwiftUI

struct KillerSyncMockup: View {

    @State private var slideOffset: CGFloat = 20
    @State private var glowOpacity: Double = 0.3

    var body: some View {
        VStack(spacing: 16) {
            videosRow
            timeChip
        }
        .onAppear { animateIn() }
    }

    private var videosRow: some View {
        HStack(spacing: 8) {
            videoTile(label: "YOU", offset: -slideOffset)
            videoTile(label: "PRO", offset: slideOffset)
        }
        .overlay(impactLine)
    }

    private func videoTile(label: String, offset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.onboardingMidGreen.opacity(0.6))
                .overlay(
                    Image(systemName: "figure.golf")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.onboardingGold.opacity(0.7))
                )

            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.5), in: Capsule())
                .padding(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: offset)
    }

    private var impactLine: some View {
        Rectangle()
            .fill(Color.onboardingGold)
            .frame(width: 2)
            .shadow(color: Color.onboardingGoldLight, radius: 12)
            .opacity(glowOpacity)
    }

    private var timeChip: some View {
        Text("0:00.34  IMPACT")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.onboardingGold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.onboardingGold.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(Color.onboardingGold.opacity(0.4), lineWidth: 1))
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3)) {
            slideOffset = 0
        }
        withAnimation(.easeInOut(duration: 1.5).repeatForever()) {
            glowOpacity = 1.0
        }
    }
}
