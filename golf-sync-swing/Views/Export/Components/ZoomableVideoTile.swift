//
//  ZoomableVideoTile.swift
//  golf-sync-swing
//
//  One swing on the export canvas, cut out of the comparison's own player, with
//  pinch-to-zoom + drag-to-pan. Behind it, unless it is blended over another swing, the
//  blurred fill the exported cell gets too (CellBackdrop) — still while the swing moves,
//  as in the file.
//
//  ⚠️ Modifier order: .offset() BEFORE .scaleEffect(). The offset is
//  multiplied by scale when rendered, which matches the
//  CellRenderer formula `panX = offset × scale × (export/screen)`.
//  Do NOT change the order without updating the renderer.
//

import SwiftUI
import AVFoundation

struct ZoomableVideoTile: View {
    let player: AVPlayer
    let cutout: SlotCutout
    @Binding var transform: VideoTransform
    var showsBackdrop = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backdrop

                CompositionSlotView(player: player, cutout: cutout, gravity: .fit)
                    .offset(x: transform.offset.x, y: transform.offset.y)
                    .scaleEffect(transform.scale)

                Color.clear
                    .contentShape(Rectangle())
                    .zoomable(
                        scale: $transform.scale,
                        offset: $transform.offset,
                        parentSize: geo.size
                    )
            }
            .clipped()
            .contentShape(Rectangle())
            .onAppear { syncContainerSize(geo.size) }
            .onChange(of: geo.size) { _, newSize in syncContainerSize(newSize) }
            .onChange(of: transform.scale) { _, _ in syncContainerSize(geo.size) }
            .onChange(of: transform.offset) { _, _ in syncContainerSize(geo.size) }
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if showsBackdrop {
            CompositionSlotView(player: player, cutout: cutout, gravity: .fill)
                .backdropBlurred()
        }
    }

    private func syncContainerSize(_ size: CGSize) {
        if transform.containerSize != size { transform.containerSize = size }
    }
}
