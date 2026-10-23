//
//  PaywallFooter.swift
//  golf-sync-swing
//
//  Utility row pinned under the CTA: Restore Purchases, Terms, Privacy.
//  App Review wants Restore and the legal links reachable from the paywall
//  at all times, so each one gets a full 44 pt target and readable contrast.
//

import SwiftUI

struct PaywallFooter: View {

    let onRestore: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        layout {
            Button("Restore Purchases", action: onRestore)
                .buttonStyle(.plain)
                .modifier(FooterTapTarget())
            Link("Terms", destination: LegalLinks.termsOfUse)
                .modifier(FooterTapTarget())
            Link("Privacy", destination: LegalLinks.privacyPolicy)
                .modifier(FooterTapTarget())
        }
        .font(.footnote)
        .foregroundStyle(Color.white.opacity(0.75))
        .frame(maxWidth: .infinity)
    }

    /// A row at regular sizes; a column at accessibility sizes, where three
    /// links side by side break mid-word.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0))
            : AnyLayout(HStackLayout(spacing: 20))
    }
}

private struct FooterTapTarget: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}
