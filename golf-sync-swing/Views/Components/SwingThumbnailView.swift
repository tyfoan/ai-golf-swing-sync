//
//  SwingThumbnailView.swift
//  golf-sync-swing
//
//  Card for a single detected swing in the Compare tab.
//  Shows impact-frame thumbnail, duration, AI confidence,
//  and a polished selection state.
//

import SwiftUI

struct SwingThumbnailView: View {
    let video: SwingVideo
    let swing: SwingMarker
    let index: Int
    let isSelected: Bool
    let selectionNumber: Int?

    @State private var thumbnailImage: UIImage?

    private let cardWidth: CGFloat = 140
    private let imageHeight: CGFloat = 100
    private let stripHeight: CGFloat = 28

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardContent
            badgeOverlays
        }
        .frame(width: cardWidth, height: imageHeight + stripHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(border)
        .shadow(
            color: isSelected ? Color.fairwayGreen.opacity(0.3) : .black.opacity(0.12),
            radius: isSelected ? 8 : 4,
            y: isSelected ? 2 : 1
        )
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .task { await loadThumbnail() }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(spacing: 0) {
            thumbnailSection
            metadataStrip
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailSection: some View {
        ZStack {
            thumbnailImage.map { image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardWidth, height: imageHeight)
                    .clipped()
            }

            if thumbnailImage == nil {
                placeholderView
            }

            if isSelected {
                Color.fairwayGreen.opacity(0.12)
            }
        }
        .frame(width: cardWidth, height: imageHeight)
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.charcoal.opacity(0.08))
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "figure.golf")
                        .font(.title3)
                        .foregroundStyle(Color.fairwayGreen.opacity(0.4))
                    Text("Swing \(index)")
                        .font(.caption2).fontWeight(.medium)
                        .foregroundStyle(Color.charcoal.opacity(0.35))
                }
            }
    }

    // MARK: - Metadata Strip

    private var metadataStrip: some View {
        HStack(spacing: 0) {
            durationLabel
            Spacer()
            confidenceBadge
        }
        .padding(.horizontal, 8)
        .frame(width: cardWidth, height: stripHeight)
        .background(Color.charcoal.opacity(0.85))
    }

    private var durationLabel: some View {
        Text(formattedDuration)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
    }

    private var confidenceBadge: some View {
        HStack(spacing: 3) {
            Text("AI")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.onboardingTealAccent)
            Circle()
                .fill(confidenceColor)
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Badge Overlays

    private var badgeOverlays: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            // Selection badge — top leading
            if let number = selectionNumber {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.fairwayGreen)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .padding(6)
            }

            // Favorite star — top trailing
            if swing.isFavorite {
                HStack {
                    Spacer()
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.sand)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .padding(6)
                }
            }
        }
    }

    // MARK: - Border

    private var border: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                isSelected ? Color.fairwayGreen : Color.charcoal.opacity(0.1),
                lineWidth: isSelected ? 2.5 : 0.5
            )
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        String(format: "%.1fs", swing.duration)
    }

    private var confidenceColor: Color {
        switch swing.detectionConfidence {
        case 0.8...: return .green
        case 0.5..<0.8: return .yellow
        default: return .orange
        }
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnail() async {
        let data = ThumbnailService.shared.generateThumbnail(
            for: video.localURL, at: swing.contactTime
        )
        guard let data else { return }
        thumbnailImage = UIImage(data: data)
    }
}
