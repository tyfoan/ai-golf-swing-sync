//
//  PaywallBackground.swift
//  golf-sync-swing
//
//  The dark green mesh gradient behind the paywall, shared with onboarding's palette.
//

import SwiftUI

struct PaywallBackground: View {

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                .onboardingDark,      .onboardingDeepGreen, .onboardingDark,
                .onboardingDeepGreen, .onboardingMidGreen,  .onboardingDeepGreen,
                .onboardingDark,      .onboardingDeepGreen, .onboardingDark
            ]
        )
        .ignoresSafeArea()
    }
}
