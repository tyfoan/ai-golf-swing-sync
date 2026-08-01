//
//  OnboardingPrimaryButton.swift
//  golf-sync-swing
//
//  Full-width capsule CTA. Vertical gradient with a bright top rim and a
//  coloured glow. The label cross-fades in place when the page changes, so
//  "Continue" dissolves into "Get Started" without the button moving.
//

import SwiftUI

struct OnboardingPrimaryButton: View {

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(PressableCapsuleStyle())
        .animation(.easeInOut(duration: 0.25), value: title)
    }

    private var label: some View {
        Text(title)
            .font(.system(size: Metrics.fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.opacity)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metrics.verticalPadding)
            .background(gradient, in: Capsule())
            .overlay { rim }
            .shadow(color: Color.onboardingCTATop.opacity(0.45), radius: 16, y: 6)
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [.onboardingCTATop, .onboardingCTABottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Light catches the top edge of a physical capsule — a flat stroke reads
    /// as a border, this reads as a highlight.
    private var rim: some View {
        Capsule().stroke(
            LinearGradient(
                colors: [.white.opacity(0.38), .white.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 1
        )
    }

    private enum Metrics {
        static let fontSize: CGFloat = 17
        static let verticalPadding: CGFloat = 16
    }
}

private struct PressableCapsuleStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
