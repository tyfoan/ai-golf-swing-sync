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
            title: String(localized: "Auto-sync at impact", comment: "Paywall feature row 1 title"),
            subtitle: String(localized: "Frame-perfect alignment with any pro.", comment: "Paywall feature row 1 subtitle")
        ),
        .init(
            id: "pro-library",
            symbol: "rectangle.stack.fill",
            title: String(localized: "Pro swing library", comment: "Paywall feature row 2 title"),
            subtitle: String(localized: "Compare to pros in onion-skin & 8× slow-mo.", comment: "Paywall feature row 2 subtitle (onion-skin = transparency overlay comparison mode)")
        ),
        .init(
            id: "hd-export",
            symbol: "square.and.arrow.up.fill",
            title: String(localized: "HD export", comment: "Paywall feature row 3 title"),
            subtitle: String(localized: "Share-ready, no watermark, multi-aspect.", comment: "Paywall feature row 3 subtitle")
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
