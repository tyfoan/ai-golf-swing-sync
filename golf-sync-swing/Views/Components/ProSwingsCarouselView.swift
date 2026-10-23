//
//  ProSwingsCarouselView.swift
//  golf-sync-swing
//
//  Horizontal carousel of bundled professional reference swings shown above
//  the user's date-grouped list on the Compare tab.
//

import SwiftUI

struct ProSwingsCarouselView: View {
    let videos: [SwingVideo]
    let selectedSwings: [SwingSelection]
    let onTap: (SwingMarker, SwingVideo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader
            cards
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Text("PRO SWINGS")
                .font(.headline).fontWeight(.bold)
                .foregroundStyle(Color.charcoal)
        }
        .padding(.horizontal)
    }

    // MARK: - Cards

    private var cards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(videos) { video in
                    if let swing = video.swings.first {
                        Button {
                            onTap(swing, video)
                        } label: {
                            ProSwingCard(
                                video: video,
                                swing: swing,
                                selectionNumber: selectionNumber(for: swing.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Selection Helpers

    private func selectionNumber(for swingId: UUID) -> Int? {
        guard let idx = selectedSwings.firstIndex(where: { $0.swingId == swingId }) else {
            return nil
        }
        return idx + 1
    }
}

// MARK: - Card

private struct ProSwingCard: View {
    let video: SwingVideo
    let swing: SwingMarker
    let selectionNumber: Int?

    private let cardWidth: CGFloat = 180
    private let cardHeight: CGFloat = 178

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                thumbnailLayer
                nameOverlay
            }
            if let number = selectionNumber {
                selectionBadge(number: number)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(selectionBorder)
    }

    private var thumbnailLayer: some View {
        Group {
            if let data = video.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.charcoal.opacity(0.2)
            }
        }
        .frame(width: cardWidth, height: 120)
        .background(Color.black)
        .clipped()
    }

    private var nameOverlay: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(video.proDisplayName ?? "Pro")
                .font(.subheadline).fontWeight(.bold)
                .lineLimit(1).minimumScaleFactor(0.8)
            if let club = video.proClub {
                Text(club).font(.caption).foregroundStyle(.white.opacity(0.85))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .background(Color.charcoal)
    }

    private func selectionBadge(number: Int) -> some View {
        Text("\(number)")
            .font(.caption).fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color.appTeal)
            .clipShape(Circle())
            .padding(8)
    }

    @ViewBuilder
    private var selectionBorder: some View {
        if selectionNumber != nil {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appTeal, lineWidth: 3)
        }
    }
}
