//
//  SlowMoToolsMockup.swift
//  golf-sync-swing
//
//  Hero animation for onboarding screen 3: golfer + animated swing
//  trajectory curve being drawn, plus timeline scrubber and 8x slo-mo chip.
//

import SwiftUI

struct SlowMoToolsMockup: View {

    @State private var trimEnd: CGFloat = 0
    @State private var indicatorPosition: CGFloat = 0.2

    var body: some View {
        VStack(spacing: 16) {
            stage
            timeline
            speedChip
        }
        .onAppear { animateIn() }
    }

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.onboardingMidGreen.opacity(0.4))

            Image(systemName: "figure.golf")
                .font(.system(size: 56))
                .foregroundStyle(Color.onboardingGold.opacity(0.7))

            trajectoryPath
                .trim(from: 0, to: trimEnd)
                .stroke(
                    Color.onboardingGold,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .shadow(color: Color.onboardingGoldLight, radius: 4)
        }
        .frame(height: 200)
    }

    private var trajectoryPath: Path {
        Path { path in
            path.move(to: CGPoint(x: 30, y: 170))
            path.addQuadCurve(
                to: CGPoint(x: 200, y: 30),
                control: CGPoint(x: 30, y: 30)
            )
        }
    }

    private var timeline: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.onboardingMidGreen)
                    .frame(height: 6)

                Capsule()
                    .fill(Color.onboardingGold)
                    .frame(width: 4, height: 16)
                    .offset(x: geo.size.width * indicatorPosition - 2, y: -5)
            }
        }
        .frame(height: 16)
    }

    private var speedChip: some View {
        HStack {
            Spacer()
            Text("8× SLO-MO")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.onboardingGold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.onboardingGold.opacity(0.15), in: Capsule())
                .overlay(Capsule().stroke(Color.onboardingGold.opacity(0.4), lineWidth: 1))
        }
    }

    private func animateIn() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
            trimEnd = 1.0
        }
        withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
            indicatorPosition = 0.8
        }
    }
}
