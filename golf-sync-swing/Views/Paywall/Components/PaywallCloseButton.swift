//
//  PaywallCloseButton.swift
//  golf-sync-swing
//
//  Always-visible close button in the paywall's top-left corner: a 32 pt circle
//  inside a 44 pt tap target. Inert while a purchase is in flight.
//

import SwiftUI

struct PaywallCloseButton: View {

    let isWorking: Bool
    let onClose: () -> Void

    var body: some View {
        VStack {
            HStack {
                button
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
            Spacer()
        }
    }

    private var button: some View {
        Button {
            // Inert mid-purchase: dismissing would fire paywall_dismissed
            // before paywall_purchased and run onDismiss twice.
            guard !isWorking else { return }
            onClose()
        } label: {
            glyph
        }
        .disabled(isWorking)
        .accessibilityLabel(Text("Close", comment: "Accessibility label of the paywall's close button"))
    }

    /// The 32 pt circle, centred in its 44 pt tap target.
    private var glyph: some View {
        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.55))
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.white.opacity(0.08)))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
