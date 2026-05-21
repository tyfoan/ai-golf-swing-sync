//
//  PositioningGuideOverlay.swift
//  golf-sync-swing
//
//  Pre-record posture preview. Hero silhouette + three framing rules over
//  a gradient scrim. Non-interactive so taps pass through to the Start
//  Recording button beneath it.
//

import SwiftUI

struct PositioningGuideOverlay: View {
    var silhouetteNamespace: Namespace.ID? = nil

    var body: some View {
        ZStack {
            backdrop
                .ignoresSafeArea()

            VStack(spacing: 26) {
                header
                silhouetteHero
                hairline
                rulesList
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.top, 60)
            .padding(.bottom, 200)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Sections

    private var backdrop: some View {
        LinearGradient(
            colors: [Color.black.opacity(0.72), Color.black.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("How It Works")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)

            Text("Record your swing and get an instant replay.\nSwings are detected automatically.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    private var silhouetteHero: some View {
        VStack(spacing: 10) {
            poseImage
            Text("Match this pose")
                .font(.subheadline.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var poseImage: some View {
        let image = Image("golfer-down-the-line")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(.white)
            .frame(height: 170)
            .shadow(color: Color.fairwayGreen.opacity(0.45), radius: 28)

        if let namespace = silhouetteNamespace {
            image.matchedGeometryEffect(id: "silhouette", in: namespace)
        } else {
            image
        }
    }

    private var hairline: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.28), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }

    private var rulesList: some View {
        VStack(spacing: 14) {
            ruleRow(icon: "figure.stand", text: "Full body in frame")
            ruleRow(icon: "person.2.slash.fill", text: "No other people in frame")
            ruleRow(icon: "sun.max.fill", text: "Don't aim at the sun")
        }
    }

    private func ruleRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(.white.opacity(0.12))
                        .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                )

            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
        PositioningGuideOverlay()
    }
}
