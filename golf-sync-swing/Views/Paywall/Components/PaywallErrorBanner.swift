//
//  PaywallErrorBanner.swift
//  golf-sync-swing
//
//  Red retry banner shown above the plans when the offering failed to load.
//  Renders nothing in every other load state.
//

import SwiftUI

struct PaywallErrorBanner: View {

    let state: PaywallViewModel.LoadState
    let onRetry: () -> Void

    var body: some View {
        if case .failed(let message) = state {
            Button(action: onRetry) {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.flagRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.flagRed.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
