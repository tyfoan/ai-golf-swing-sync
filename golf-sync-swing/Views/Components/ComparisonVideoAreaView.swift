//
//  ComparisonVideoAreaView.swift
//  golf-sync-swing
//
//  Renders the single AVPlayer driving the comparison composition. The mode
//  (sideBySide, topBottom, stacked, sequential) and swap state are baked into
//  the composition's videoComposition layer instructions — SwiftUI just shows
//  the composited output.
//

import SwiftUI
import AVFoundation

struct ComparisonVideoAreaView: View {
    let viewModel: ComparisonViewModel

    var body: some View {
        GeometryReader { geometry in
            VideoPlayerView(player: viewModel.player)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { viewModel.togglePlayPause() }
        }
    }
}
