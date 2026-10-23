//
//  PaywallToast.swift
//  golf-sync-swing
//
//  A short message capsule near the bottom of the paywall. Each message has its
//  own identity, so a newer one is never cleared by an older one's timer.
//

import SwiftUI

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

struct PaywallToast: View {

    let toast: ToastMessage?

    var body: some View {
        if let toast {
            VStack {
                Spacer()
                capsule(toast.text)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .id(toast.id)
        }
    }

    private func capsule(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.charcoal.opacity(0.92)))
    }
}
