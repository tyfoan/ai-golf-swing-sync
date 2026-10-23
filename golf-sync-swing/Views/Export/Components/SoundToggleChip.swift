//
//  SoundToggleChip.swift
//  golf-sync-swing
//
//  A glass capsule that turns one swing's sound on or off in the export, named for the
//  swing — so it says whose sound it is, and sits below the canvas rather than on it.
//

import SwiftUI

struct SoundToggleChip: View {
    let label: PaneLabel
    @Binding var isMuted: Bool

    var body: some View {
        Button { isMuted.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .contentTransition(.symbolEffect(.replace))
                Text(verbatim: label.title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary.opacity(isMuted ? 0.5 : 1))
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label.title))
        .accessibilityValue(isMuted ? Text("Muted") : Text("Sound on"))
    }
}
