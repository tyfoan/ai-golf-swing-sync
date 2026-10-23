//
//  PaywallFeatureList.swift
//  golf-sync-swing
//
//  Icon-title-subtitle rows under the hero. Each row is something the free
//  tier really lacks — the library cap, the one free pro comparison, the
//  locked modes and the HD export tiers — so the paywall never sells a perk
//  the user already has.
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
            id: "every-comparison",
            symbol: "figure.golf",
            title: String(localized: "Every swing vs every pro", comment: "Paywall feature row title: premium lifts the one-free-comparison limit"),
            subtitle: String(localized: "Compare all your swings with the pro library, synced at impact.", comment: "Paywall feature row subtitle under 'Every swing vs every pro'")
        ),
        .init(
            id: "unlimited-library",
            symbol: "square.stack.3d.up.fill",
            title: String(localized: "Unlimited swing library", comment: "Paywall feature row title: premium removes the 3-recording cap"),
            subtitle: String(localized: "Keep every recording. Free accounts keep 3.", comment: "Paywall feature row subtitle under 'Unlimited swing library'")
        ),
        .init(
            id: "comparison-modes",
            symbol: "square.on.square",
            title: String(localized: "Stacked & sequential modes", comment: "Paywall feature row title. Stacked and Sequential are the names of two comparison modes in the app"),
            subtitle: String(localized: "Overlay your swing on a pro's, or play them back to back.", comment: "Paywall feature row subtitle explaining the Stacked and Sequential modes")
        ),
        .init(
            id: "hd-export",
            symbol: "square.and.arrow.up.fill",
            title: String(localized: "HD export", comment: "Paywall feature row 3 title"),
            subtitle: String(localized: "Share-ready 1080p and 1440p clips.", comment: "Paywall feature row subtitle under 'HD export'; 1080p and 1440p are video resolutions")
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
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        Image(systemName: row.symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Color.onboardingGold)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }
}
