//
//  VideoFloatingActionsView.swift
//  golf-sync-swing
//
//  Floating action buttons on the right side of the video player.
//  Favorite (swings only), mute toggle, pose placeholder.
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
            poseButton
        }
        .padding(8)
    }

    // MARK: - Buttons

    private var favoriteButton: some View {
        FloatingCircleButton(
            icon: isFavorite ? "star.fill" : "star",
            tint: isFavorite ? .yellow : .white.opacity(0.6),
            action: onToggleFavorite
        )
    }

    private var muteButton: some View {
        FloatingCircleButton(
            icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            tint: .white.opacity(0.6),
            action: onToggleMute
        )
    }

    private var poseButton: some View {
        FloatingCircleButton(
            icon: "figure.stand",
            tint: .white.opacity(0.3),
            action: {}
        )
        .disabled(true)
    }
}

// MARK: - Reusable Circle Button

private struct FloatingCircleButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Color(.systemGray5).opacity(0.8))
                .clipShape(Circle())
        }
    }
}
