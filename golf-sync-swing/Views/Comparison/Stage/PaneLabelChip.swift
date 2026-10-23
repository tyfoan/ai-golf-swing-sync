//
//  PaneLabelChip.swift
//  golf-sync-swing
//
//  The small glass capsule in a pane's corner that says whose swing it is. Always dark
//  glass: it sits on the video, not on the cream stage.
//

import SwiftUI

struct PaneLabelChip: View {
    let label: PaneLabel

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: label.title).fontWeight(.semibold)
            Text(verbatim: label.detail).foregroundStyle(.white.opacity(0.7))
        }
        .font(.caption)
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        // Tinted dark: plain glass over a white sky turns white itself and the name vanishes.
        .glassEffect(.regular.tint(.black.opacity(0.35)), in: .capsule)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}
