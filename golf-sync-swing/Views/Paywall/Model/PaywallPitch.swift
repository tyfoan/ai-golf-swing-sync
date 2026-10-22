//
//  PaywallPitch.swift
//  golf-sync-swing
//
//  The words at the top of the paywall. Each headline is one string whose line
//  breaks belong to the translation, so every language keeps its own word order.
//  Pitches are looked up by source rather than switched over.
//

import Foundation

struct PaywallPitch {

    let headline: LocalizedStringResource
    let subheadline: LocalizedStringResource

    static func of(_ source: PaywallSource) -> PaywallPitch {
        pitches[source] ?? featureGate
    }

    private static let pitches: [PaywallSource: PaywallPitch] = [
        .featureGate: featureGate,
        .settings: settings
    ]

    private static let featureGate = PaywallPitch(
        headline: LocalizedStringResource(
            "Unlock\nthe full\ncomparison.",
            comment: "Paywall headline shown when a locked feature is tapped. Three short lines; place the line breaks where they read naturally"
        ),
        subheadline: LocalizedStringResource(
            "Stacked and sequential modes, every swing against every pro, and HD export.",
            comment: "Paywall subheadline under the locked-feature headline. Stacked and Sequential are the names of two comparison modes in the app"
        )
    )

    private static let settings = PaywallPitch(
        headline: LocalizedStringResource(
            "Go Pro.\nEvery mode.\nEvery swing.",
            comment: "Paywall headline when opened from Settings. Three short lines; place the line breaks where they read naturally"
        ),
        subheadline: LocalizedStringResource(
            "An unlimited swing library, every comparison mode and HD export.",
            comment: "Paywall subheadline when opened from Settings"
        )
    )
}
