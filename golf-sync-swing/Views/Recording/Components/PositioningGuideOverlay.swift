//
//  PositioningGuideOverlay.swift
//  golf-sync-swing
//
//  Full-screen dark overlay with best practice rules on camera
//

import SwiftUI

struct PositioningGuideOverlay: View {
    var body: some View {
        ZStack {
            // Dark scrim for contrast
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // How it works
                VStack(spacing: 10) {
                    Text("How It Works")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Record your swing and get an instant replay.\nSwings are detected automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                // Rules
                VStack(spacing: 24) {
                    ruleRow(icon: "figure.stand", text: "Full body in frame")
                    ruleRow(icon: "person.2.slash.fill", text: "No other people in frame")
                    ruleRow(icon: "sun.max.fill", text: "Face a light source")
                }
            }
            .padding(.horizontal, 40)
        }
    }

    private func ruleRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.fairwayGreen)
                .frame(width: 36)

            Text(text)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)

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
