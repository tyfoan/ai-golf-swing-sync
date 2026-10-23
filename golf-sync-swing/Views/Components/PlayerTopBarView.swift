//
//  PlayerTopBarView.swift
//  golf-sync-swing
//
//  Top bar of the single video player: glass circle buttons (back, share), as on the
//  comparison, with the mode picker in a glass capsule between them.
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
        StageIconButton(symbol: "chevron.backward", label: "Back", action: onDismiss)
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
                Text(playbackMode.displayName)
                    .font(.subheadline).fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    // MARK: - Share

    private var shareButton: some View {
        StageIconButton(symbol: "square.and.arrow.up", label: "Export video", action: onExport)
    }
}
