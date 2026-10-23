//
//  StageSwapButton.swift
//  golf-sync-swing
//
//  The round glass button that trades the two swings' places, sitting on the seam
//  between the panes.
//

import SwiftUI

struct StageSwapButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Swap videos"))
    }
}
