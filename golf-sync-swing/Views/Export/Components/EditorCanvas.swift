//
//  EditorCanvas.swift
//  golf-sync-swing
//
//  Arranges two zoomable tiles side-by-side or stacked, sized to fit
//  the chosen export aspect ratio inside the available preview area.
//

import SwiftUI
import AVFoundation

struct EditorCanvas: View {
    let aspectRatio: ExportAspectRatio
    let player1: AVPlayer
    let player2: AVPlayer
    @Binding var transform1: VideoTransform
    @Binding var transform2: VideoTransform

    var body: some View {
        GeometryReader { geo in
            let canvas = sizeFitting(aspectRatio: aspectRatio.ratio, into: geo.size)
            arrangedTiles(canvas: canvas)
                .frame(width: canvas.width, height: canvas.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func arrangedTiles(canvas: CGSize) -> some View {
        switch aspectRatio.arrangement {
        case .horizontal:
            HStack(spacing: 0) {
                tile(player: player1, transform: $transform1)
                tile(player: player2, transform: $transform2)
            }
        case .vertical:
            VStack(spacing: 0) {
                tile(player: player1, transform: $transform1)
                tile(player: player2, transform: $transform2)
            }
        }
    }

    private func tile(player: AVPlayer, transform: Binding<VideoTransform>) -> some View {
        ZStack(alignment: .bottomLeading) {
            ZoomableVideoTile(player: player, transform: transform)
            MuteToggleButton(isMuted: Binding(
                get: { transform.wrappedValue.isMuted },
                set: { transform.wrappedValue.isMuted = $0 }
            ))
            .padding(8)
        }
    }

    private func sizeFitting(aspectRatio: CGFloat, into size: CGSize) -> CGSize {
        let containerRatio = size.width / size.height
        if containerRatio > aspectRatio {
            return CGSize(width: size.height * aspectRatio, height: size.height)
        } else {
            return CGSize(width: size.width, height: size.width / aspectRatio)
        }
    }
}
