//
//  EditorCanvas.swift
//  golf-sync-swing
//
//  Mode-aware canvas. Branches by ComparisonMode:
//  - sideBySide: two tiles arranged HSTACK/VSTACK per aspect.
//  - stacked: two tiles overlaid full-canvas; video 2 at user-set opacity.
//  - sequential: one full-canvas tile + a Swing 1 / Swing 2 segmented toggle.
//

import SwiftUI
import AVFoundation

struct EditorCanvas: View {
    let aspectRatio: ExportAspectRatio
    let mode: ComparisonMode
    let stackedOpacity: CGFloat
    let player1: AVPlayer
    let player2: AVPlayer
    @Binding var transform1: VideoTransform
    @Binding var transform2: VideoTransform
    @Binding var sequentialEditIndex: Int

    var body: some View {
        VStack(spacing: 12) {
            if mode.showsSequentialPicker {
                sequentialPicker
            }
            GeometryReader { geo in
                let canvas = sizeFitting(aspectRatio: aspectRatio.ratio, into: geo.size)
                canvasContent(canvas: canvas)
                    .frame(width: canvas.width, height: canvas.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func canvasContent(canvas: CGSize) -> some View {
        switch mode {
        case .sideBySide:
            sideBySideTiles
        case .stacked:
            stackedTiles
        case .sequential:
            sequentialTile
        }
    }

    @ViewBuilder
    private var sideBySideTiles: some View {
        switch aspectRatio.arrangement {
        case .horizontal:
            HStack(spacing: 0) { tile1; tile2 }
        case .vertical:
            VStack(spacing: 0) { tile1; tile2 }
        }
    }

    private var stackedTiles: some View {
        ZStack {
            tile1
            tile2.opacity(stackedOpacity)
        }
    }

    @ViewBuilder
    private var sequentialTile: some View {
        if sequentialEditIndex == 0 {
            tile1
        } else {
            tile2
        }
    }

    private var tile1: some View {
        ZStack(alignment: .bottomLeading) {
            ZoomableVideoTile(player: player1, transform: $transform1)
            MuteToggleButton(isMuted: Binding(
                get: { transform1.isMuted },
                set: { transform1.isMuted = $0 }
            ))
            .padding(8)
        }
    }

    private var tile2: some View {
        ZStack(alignment: .bottomLeading) {
            ZoomableVideoTile(player: player2, transform: $transform2)
            MuteToggleButton(isMuted: Binding(
                get: { transform2.isMuted },
                set: { transform2.isMuted = $0 }
            ))
            .padding(8)
        }
    }

    private var sequentialPicker: some View {
        Picker("", selection: $sequentialEditIndex) {
            Text("Swing 1").tag(0)
            Text("Swing 2").tag(1)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
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
