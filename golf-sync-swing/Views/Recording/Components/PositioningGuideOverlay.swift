//
//  PositioningGuideOverlay.swift
//  golf-sync-swing
//
//  Full-screen dark overlay with best practice rules on camera
//

import SwiftUI

struct PositioningGuideOverlay: View {
    var silhouetteNamespace: Namespace.ID? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Text("How It Works")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Record your swing and get an instant replay.\nSwings are detected automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 6) {
                    poseExample
                    Text("Match this pose")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    ruleRow(icon: "figure.stand", text: "Full body in frame")
                    ruleRow(icon: "person.2.slash.fill", text: "No other people in frame")
                    ruleRow(icon: "sun.max.fill", text: "Don't aim at the sun")
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 200)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var poseExample: some View {
        let image = Image("golfer-down-the-line")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(.white.opacity(0.9))
            .frame(height: 120)
            .shadow(color: Color.fairwayGreen.opacity(0.55), radius: 18)

        if let namespace = silhouetteNamespace {
            image.matchedGeometryEffect(id: "silhouette", in: namespace)
        } else {
            image
        }
    }

    private func ruleRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28)

            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

#Preview {
    ZStack {
        Color.gray
        PositioningGuideOverlay()
    }
}
