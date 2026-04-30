//
//  MuteToggleButton.swift
//  golf-sync-swing
//

import SwiftUI

struct MuteToggleButton: View {
    @Binding var isMuted: Bool

    var body: some View {
        Button { isMuted.toggle() } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(Circle().fill(.black.opacity(0.55)))
        }
        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
    }
}
