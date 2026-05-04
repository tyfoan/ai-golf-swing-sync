//
//  PhoneFrameView.swift
//  golf-sync-swing
//
//  Phone-frame container for onboarding hero mockups.
//  Provides consistent shape, gradient fill, and shadow.
//

import SwiftUI

struct PhoneFrameView<Content: View>: View {

    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(
                LinearGradient(
                    colors: [Color.onboardingDark, Color.onboardingDeepGreen],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
            )
            .overlay(content().padding(16))
            .frame(width: 260, height: 360)
            .shadow(color: Color.black.opacity(0.4), radius: 20, y: 8)
    }
}
