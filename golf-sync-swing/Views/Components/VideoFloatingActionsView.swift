//
//  VideoFloatingActionsView.swift
//  golf-sync-swing
//
//  Floating action buttons on the right side of the video player.
//  Favorite (swings only) and mute toggle, in dark glass over the video.
//

import SwiftUI

struct VideoFloatingActionsView: View {
    let isFavorite: Bool
    let isMuted: Bool
    let showFavorite: Bool
    let onToggleFavorite: () -> Void
    let onToggleMute: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if showFavorite {
                favoriteButton
            }
            muteButton
        }
        .padding(8)
    }

    // MARK: - Buttons

    private var favoriteButton: some View {
        FloatingCircleButton(
            icon: isFavorite ? "star.fill" : "star",
            tint: isFavorite ? .yellow : .white.opacity(0.8),
            label: Text("Favorite", comment: "Accessibility label of the star button that marks a swing as a favorite"),
            action: onToggleFavorite
        )
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }

    private var muteButton: some View {
        FloatingCircleButton(
            icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            tint: .white.opacity(0.8),
            label: isMuted ? Text("Muted") : Text("Sound on"),
            action: onToggleMute
        )
    }
}

// MARK: - Reusable Circle Button

/// Dark-tinted glass, because it always sits on the video: plain glass over a white sky
/// turns white itself and swallows the icon.
private struct FloatingCircleButton: View {
    let icon: String
    let tint: Color
    let label: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(.black.opacity(0.35)).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(label)
    }
}
