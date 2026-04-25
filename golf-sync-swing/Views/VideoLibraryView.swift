//
//  VideoLibraryView.swift
//  golf-sync-swing
//

import SwiftUI
import SwiftData

struct VideoLibraryView: View {
    let videos: [SwingVideo]
    let selectedVideos: Set<UUID>
    let onVideoSelect: (SwingVideo) -> Void
    let onVideoPlay: (SwingVideo) -> Void
    let onVideoDelete: (SwingVideo) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        if videos.isEmpty {
            ContentUnavailableView(
                "No Videos",
                systemImage: "video.badge.plus",
                description: Text("Import videos from your library to get started")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(videos) { video in
                        VideoRowView(
                            video: video,
                            isSelected: selectedVideos.contains(video.id),
                            onSelect: { onVideoSelect(video) },
                            onPlay: { onVideoPlay(video) }
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                onVideoDelete(video)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
}
