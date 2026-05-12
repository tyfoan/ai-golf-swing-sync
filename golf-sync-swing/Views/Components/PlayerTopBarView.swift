//
//  PlayerTopBarView.swift
//  golf-sync-swing
//
//  Custom top bar for the immersive single video player.
//  Teal circle buttons (back, share) with center mode picker.
//

import SwiftUI

struct PlayerTopBarView: View {
    let playbackMode: VideoPlaybackMode
    let onDismiss: () -> Void
    let onSwitchMode: (VideoPlaybackMode) -> Void
    let onExport: () -> Void

    var body: some View {
        HStack {
            backButton
            Spacer()
            modePicker
            Spacer()
            shareButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Back

    private var backButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "chevron.left")
                .font(.body).fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.appTeal)
                .clipShape(Circle())
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Menu {
            ForEach(VideoPlaybackMode.allCases, id: \.self) { mode in
                Button {
                    onSwitchMode(mode)
                } label: {
                    HStack {
                        Text(mode.displayName)
                        if mode == playbackMode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(playbackMode.rawValue)
                    .font(.subheadline).fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
        }
    }

    // MARK: - Share

    private var shareButton: some View {
        Button(action: onExport) {
            Image(systemName: "square.and.arrow.up")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.appTeal)
                .clipShape(Circle())
        }
        .accessibilityLabel("Export video")
    }
}
