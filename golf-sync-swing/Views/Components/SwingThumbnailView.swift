//
//  SwingThumbnailView.swift
//  golf-sync-swing
//
//  Compact thumbnail card for a single detected swing.
//

import SwiftUI

struct SwingThumbnailView: View {
    let video: SwingVideo
    let swing: SwingMarker
    let index: Int
    let isSelected: Bool
    let selectionNumber: Int?

    @State private var thumbnailImage: UIImage?

    private let thumbnailSize = CGSize(width: 72, height: 96)

    var body: some View {
        ZStack(alignment: .topLeading) {
            thumbnailContent
            selectionBadge
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(selectionBorder)
        .task { await loadThumbnail() }
    }

    // MARK: - Thumbnail Content

    @ViewBuilder
    private var thumbnailContent: some View {
        if let image = thumbnailImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .clipped()
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            .overlay {
                VStack(spacing: 2) {
                    Image(systemName: "figure.golf")
                        .font(.body).foregroundStyle(Color.appTeal.opacity(0.6))
                    Text("\(index)")
                        .font(.caption2).fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
    }

    // MARK: - Selection

    @ViewBuilder
    private var selectionBadge: some View {
        if let number = selectionNumber {
            Text("\(number)")
                .font(.system(size: 10)).fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.appTeal)
                .clipShape(Circle())
                .padding(4)
        }
    }

    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(isSelected ? Color.appTeal : .white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
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
