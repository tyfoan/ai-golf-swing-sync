//
//  PaywallFeatureRow.swift
//  golf-sync-swing
//
//  A single feature row for the paywall feature list.
//

import SwiftUI

struct PaywallFeatureRow: View {

    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.onboardingTealAccent)
                .frame(width: 36, height: 36)
                .background(Color.onboardingTealAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "checkmark")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.onboardingTealAccent)
        }
    }
}
