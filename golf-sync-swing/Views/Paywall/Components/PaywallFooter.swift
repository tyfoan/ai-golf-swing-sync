//
//  PaywallFooter.swift
//  golf-sync-swing
//
//  Tiny utility row under the CTA: Restore Purchases, Terms, Privacy.
//  Required by App Review (Restore must be reachable from any paywall).
//

import SwiftUI

struct PaywallFooter: View {

    let onRestore: () -> Void

    private static let termsURL = URL(string: "https://withcoach.app/terms")!
    private static let privacyURL = URL(string: "https://withcoach.app/privacy")!

    var body: some View {
        HStack(spacing: 24) {
            Button("Restore Purchases", action: onRestore)
                .buttonStyle(.plain)
            Link("Terms", destination: Self.termsURL)
            Link("Privacy", destination: Self.privacyURL)
        }
        .font(.caption2)
        .foregroundStyle(Color.white.opacity(0.4))
    }
}
