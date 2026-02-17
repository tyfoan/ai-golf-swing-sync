//
//  SwingSelectionListView.swift
//  golf-sync-swing
//
//  Date-grouped swing selection list for the Compare tab.
//

import SwiftUI

struct SwingSelectionListView: View {
    let groups: [VideoDateGroup]
    let selectedSwings: [SwingSelection]
    let onSwingTap: (SwingMarker, SwingVideo) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(groups, id: \.date) { group in
                    dateSection(group)
                }
            }
            .padding()
        }
    }

    // MARK: - Date Section

    private func dateSection(_ group: VideoDateGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.date).font(.headline).fontWeight(.bold)
                .foregroundStyle(Color.charcoal)

            ForEach(group.videos) { video in
                swingRow(for: video)
            }
        }
    }

    @ViewBuilder
    private func swingRow(for video: SwingVideo) -> some View {
        if video.swings.isEmpty {
            Text("No swings detected")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.leading, 4)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                videoTimeLabel(for: video)
                swingThumbnailStrip(for: video)
            }
        }
    }

    private func videoTimeLabel(for video: SwingVideo) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundStyle(Color.charcoal.opacity(0.35))
            Text(Self.timeFormatter.string(from: video.createdAt))
                .font(.caption).foregroundStyle(Color.charcoal.opacity(0.5))
            Text("\u{2022}")
                .font(.caption2).foregroundStyle(Color.charcoal.opacity(0.25))
            Text("\(video.swings.count) swing\(video.swings.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(Color.charcoal.opacity(0.5))
        }
        .padding(.leading, 2)
    }

    private func swingThumbnailStrip(for video: SwingVideo) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(video.swings.enumerated()), id: \.element.id) { idx, swing in
                    SwingThumbnailView(
                        video: video, swing: swing, index: idx + 1,
                        isSelected: isSelected(swing.id),
                        selectionNumber: selectionNumber(for: swing.id)
                    )
                    .onTapGesture { onSwingTap(swing, video) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Formatters

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    // MARK: - Selection Queries

    private func isSelected(_ swingId: UUID) -> Bool {
        selectedSwings.contains { $0.swingId == swingId }
    }

    private func selectionNumber(for swingId: UUID) -> Int? {
        guard let idx = selectedSwings.firstIndex(where: { $0.swingId == swingId }) else {
            return nil
        }
        return idx + 1
    }
}
