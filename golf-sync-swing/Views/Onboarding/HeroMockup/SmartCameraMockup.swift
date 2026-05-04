//
//  SmartCameraMockup.swift
//  golf-sync-swing
//
//  Hero animation for onboarding screen 2: viewfinder with golfer
//  silhouette and a pulsing detection bracket.
//

import SwiftUI

struct SmartCameraMockup: View {

    @State private var bracketScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            viewfinder
            golferSilhouette
            detectionBracket
            recPill
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever().delay(0.4)) {
                bracketScale = 1.05
            }
        }
    }

    private var viewfinder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.onboardingMidGreen.opacity(0.6))
    }

    private var golferSilhouette: some View {
        Image(systemName: "figure.golf")
            .font(.system(size: 80))
            .foregroundStyle(Color.onboardingGold.opacity(0.7))
    }

    private var detectionBracket: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.onboardingGold, lineWidth: 3)
            .frame(width: 130, height: 190)
            .scaleEffect(bracketScale)
    }

    private var recPill: some View {
        VStack {
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("REC")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.5), in: Capsule())
                Spacer()
            }
            Spacer()
        }
        .padding(8)
    }
}
