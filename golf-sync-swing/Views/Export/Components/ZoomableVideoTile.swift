//
//  ZoomableVideoTile.swift
//  golf-sync-swing
//
//  One swing on the export canvas, cut out of the comparison's own player, with
//  pinch-to-zoom + drag-to-pan. The swing is a card cut to its own shape, kept inside
//  the tile's rounded frame, on the cream canvas — the shapes CardMask cuts in the file.
//
//  ⚠️ Modifier order: .offset() BEFORE .scaleEffect(). The offset is
//  multiplied by scale when rendered, which matches the
//  CellRenderer formula `panX = offset × scale × (export/screen)`.
//  Do NOT change the order without updating the renderer. The card is rounded before
//  .scaleEffect(), so its corners grow with the zoom, as CellRenderer's do.
//

import SwiftUI
import AVFoundation

struct ZoomableVideoTile: View {
    let player: AVPlayer
    let cutout: SlotCutout
    @Binding var transform: VideoTransform
    /// The card's rounding, the same share of the canvas as in the file.
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                card
                gestures(in: geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(cardShape)
            .contentShape(Rectangle())
            .onAppear { syncContainerSize(geo.size) }
            .onChange(of: geo.size) { _, newSize in syncContainerSize(newSize) }
            .onChange(of: transform.scale) { _, _ in syncContainerSize(geo.size) }
            .onChange(of: transform.offset) { _, _ in syncContainerSize(geo.size) }
        }
    }

    /// The swing cut to its own shape, then panned and zoomed (offset before scale).
    private var card: some View {
        CompositionSlotView(player: player, cutout: cutout, gravity: .fill)
            .aspectRatio(cutout.slot.size, contentMode: .fit)
            .clipShape(cardShape)
            .offset(x: transform.offset.x, y: transform.offset.y)
            .scaleEffect(transform.scale)
    }

    private func gestures(in size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .zoomable(scale: $transform.scale, offset: $transform.offset, parentSize: size)
    }

    /// Circular corners: what Core Image's rounded-rectangle generator draws in the file.
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
    }

    private func syncContainerSize(_ size: CGSize) {
        if transform.containerSize != size { transform.containerSize = size }
    }
}
