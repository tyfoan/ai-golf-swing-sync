//
//  PaywallFeatureList.swift
//  golf-sync-swing
//
//  Three icon-title-subtitle rows under the hero. Same three benefits the
//  onboarding teaches, restated compact for the paywall.
//

import SwiftUI

struct PaywallFeatureList: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Self.rows) { row in
                PaywallFeatureRow(row: row)
            }
        }
    }

    static let rows: [PaywallFeatureRow.Model] = [
        .init(
            id: "auto-sync",
            symbol: "figure.golf",
            title: "Auto-sync at impact",
            subtitle: "Frame-perfect alignment with any pro."
        ),
        .init(
            id: "slowmo",
            symbol: "slowmo",
            title: "Slow-mo + drawing tools",
            subtitle: "8× slow-motion, lines, angles, HD export."
        ),
        .init(
            id: "onion",
            symbol: "square.on.square",
            title: "Onion-skin & overlay",
            subtitle: "Compare like a coach."
        )
    ]
}

struct PaywallFeatureRow: View {

    struct Model: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let subtitle: String
    }

    let row: Model

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(row.subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var icon: some View {
        Image(systemName: row.symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Color.onboardingGold)
            .frame(width: 28, height: 28)
    }
}
