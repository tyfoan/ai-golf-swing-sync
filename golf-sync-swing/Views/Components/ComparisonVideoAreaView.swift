//
//  ComparisonVideoAreaView.swift
//  golf-sync-swing
//
//  Renders dual video players in the active ComparisonMode:
//  side-by-side, stacked (with opacity blend), or sequential.
//

import SwiftUI
import AVFoundation

struct ComparisonVideoAreaView: View {
    let viewModel: ComparisonViewModel

    var body: some View {
        GeometryReader { geometry in
            modeLayout(geometry: geometry)
        }
    }
}

// MARK: - Mode Layouts

private extension ComparisonVideoAreaView {
    @ViewBuilder
    func modeLayout(geometry: GeometryProxy) -> some View {
        switch viewModel.comparisonMode {
        case .sideBySide:
            sideBySideLayout(geometry: geometry)
        case .topBottom:
            topBottomLayout(geometry: geometry)
        case .stacked:
            stackedLayout(geometry: geometry)
        case .sequential:
            sequentialLayout(geometry: geometry)
        }
    }

    func sideBySideLayout(geometry: GeometryProxy) -> some View {
        HStack(spacing: 2) {
            ForEach(viewModel.orderedPlayers, id: \.self) { player in
                videoPanel(player: player, width: geometry.size.width / 2 - 1)
            }
        }
        .frame(maxHeight: .infinity)
    }

    func topBottomLayout(geometry: GeometryProxy) -> some View {
        VStack(spacing: 2) {
            ForEach(viewModel.orderedPlayers, id: \.self) { player in
                videoPanel(player: player, height: geometry.size.height / 2 - 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    func stackedLayout(geometry: GeometryProxy) -> some View {
        ZStack {
            ForEach(Array(viewModel.orderedPlayers.enumerated()), id: \.offset) { index, player in
                VideoPlayerView(player: player)
                    .opacity(index == 0 ? 1.0 : Double(viewModel.stackedOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .onTapGesture { viewModel.togglePlayPause() }
    }

    func sequentialLayout(geometry: GeometryProxy) -> some View {
        ZStack {
            VideoPlayerView(player: viewModel.orderedPlayers[viewModel.currentSequentialSwing])
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .onTapGesture { viewModel.togglePlayPause() }
    }
}

// MARK: - Video Panel

private extension ComparisonVideoAreaView {
    func videoPanel(player: AVPlayer, width: CGFloat) -> some View {
        VideoPlayerView(player: player)
            .frame(width: width)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { viewModel.togglePlayPause() }
    }

    func videoPanel(player: AVPlayer, height: CGFloat) -> some View {
        VideoPlayerView(player: player)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { viewModel.togglePlayPause() }
    }
}
