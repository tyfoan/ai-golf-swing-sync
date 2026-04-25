//
//  VideoRowView.swift
//  golf-sync-swing
//

import SwiftUI

struct VideoRowView: View {
    let video: SwingVideo
    let isSelected: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Thumbnail with tap to select
            ZStack {
                if let thumbnailData = video.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                    Image(systemName: "video.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }

                // Selection overlay
                if isSelected {
                    Color.accentColor.opacity(0.3)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 3)
                }

                // Selection checkmark (top-right)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.8), isSelected ? Color.accentColor : Color.black.opacity(0.3))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                // Play button (center)
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }

            // Duration
            Text(formatDuration(video.duration))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
