//
//  CountdownView.swift
//  golf-sync-swing
//
//  Countdown overlay before recording starts
//

import SwiftUI

struct CountdownView: View {
    let count: Int
    let onCancel: () -> Void
    var silhouetteNamespace: Namespace.ID? = nil

    @State private var scale: CGFloat = 1.5
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            SilhouetteCutout(stance: .downTheLine, silhouetteNamespace: silhouetteNamespace)

            VStack(spacing: 14) {
                countdownDigit
                hintLabel
                Spacer()
                cancelButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
        .onChange(of: count) { _, _ in animateCountdown() }
        .onAppear { animateCountdown() }
    }

    private var hintLabel: some View {
        Text("Match the outline")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.4)))
    }

    private var countdownDigit: some View {
        Text("\(count)")
            .font(.system(size: 96, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 4)
            .scaleEffect(scale)
            .opacity(opacity)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text("CANCEL")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
        }
    }

    private func animateCountdown() {
        scale = 1.5
        opacity = 0
        withAnimation(.easeOut(duration: 0.3)) {
            scale = 1.0
            opacity = 1.0
        }
        withAnimation(.easeIn(duration: 0.3).delay(0.5)) {
            scale = 0.8
            opacity = 0
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
        CountdownView(count: 3, onCancel: {})
    }
}
