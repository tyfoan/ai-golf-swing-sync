//
//  ZoomableVideoTile.swift
//  golf-sync-swing
//
//  SwiftUI tile that renders a video with pinch-to-zoom + drag-to-pan.
//  Pattern ported from video-collage's AdjustCellView.
//
//  ⚠️ Modifier order: .offset() BEFORE .scaleEffect(). The offset is
//  multiplied by scale when rendered, which matches the
//  ExportLayoutRenderer formula `panX = offset × scale × (export/screen)`.
//  Do NOT change the order without updating the renderer.
//

import SwiftUI
import AVFoundation

struct ZoomableVideoTile: View {
    let player: AVPlayer
    @Binding var transform: VideoTransform

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                EditorVideoPlayerView(player: player)
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

    private func syncContainerSize(_ size: CGSize) {
        if transform.containerSize != size { transform.containerSize = size }
    }
}
