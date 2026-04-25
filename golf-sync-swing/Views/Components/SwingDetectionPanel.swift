//
//  SwingDetectionPanel.swift
//  golf-sync-swing
//
//  Swing section below the video player.
//  Header with edit/add actions, right-aligned thumbnail strip.
//

import SwiftUI

struct SwingDetectionPanel: View {
    @Bindable var video: SwingVideo
    let selectedSwingId: UUID?
    let isAnalyzing: Bool
    let analysisProgress: Float
    let analysisStatus: String
    var onAddNew: () -> Void
    var onEditSelected: () -> Void
    var onSwingTap: (SwingMarker) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Swings")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.white)

            Spacer()

            if selectedSwingId != nil && !video.swings.isEmpty {
                Button { onEditSelected() } label: {
                    Label("EDIT", systemImage: "pencil")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.appTeal)
                }
            }

            Button { onAddNew() } label: {
                Label("ADD", systemImage: "plus")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.appTeal)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isAnalyzing {
            analysisProgressView
        } else if video.swings.isEmpty {
            emptySwingsView
        } else {
            swingThumbnailStrip
        }
    }

    // MARK: - Thumbnail Strip

    private var swingThumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ForEach(Array(video.swings.enumerated()), id: \.element.id) { index, swing in
                        SwingThumbnailView(
                            video: video,
                            swing: swing,
                            index: index + 1,
                            isSelected: selectedSwingId == swing.id,
                            selectionNumber: index + 1
                        )
                        .id(swing.id)
                        .onTapGesture { onSwingTap(swing) }
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: selectedSwingId) { _, newId in
                guard let id = newId else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .trailing)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptySwingsView: some View {
        Text("No swings detected. Tap \u{201C}+ ADD\u{201D} to mark one manually.")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.4))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Analysis Progress

    private var analysisProgressView: some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(analysisProgress))
                .progressViewStyle(.linear)
                .tint(.appTeal)

            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text(analysisStatus.isEmpty ? "Analyzing swing..." : analysisStatus)
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal)
    }
}
