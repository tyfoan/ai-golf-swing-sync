//
//  ComparisonVideoAreaView.swift
//  golf-sync-swing
//
//  Renders dual video players in the active ComparisonMode:
//  side-by-side, synced side-by-side, onion skin, or overlay.
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
        case .sideBySide, .sideBySideSynced:
            sideBySideLayout(geometry: geometry)
        case .onionSkin:
            onionSkinLayout(geometry: geometry)
        case .overlay:
            overlayLayout(geometry: geometry)
        }
    }

    func sideBySideLayout(geometry: GeometryProxy) -> some View {
        HStack(spacing: 2) {
            videoPanel(player: viewModel.effectivePlayer1, width: geometry.size.width / 2 - 1)
            videoPanel(player: viewModel.effectivePlayer2, width: geometry.size.width / 2 - 1)
        }
        .frame(maxHeight: .infinity)
    }

    func onionSkinLayout(geometry: GeometryProxy) -> some View {
        ZStack {
            VideoPlayerView(player: viewModel.effectivePlayer1)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VideoPlayerView(player: viewModel.effectivePlayer2)
                .opacity(viewModel.onionSkinOpacity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .onTapGesture { viewModel.togglePlayPause() }
    }

    func overlayLayout(geometry: GeometryProxy) -> some View {
        ZStack {
            VideoPlayerView(player: viewModel.effectivePlayer1)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VideoPlayerView(player: viewModel.effectivePlayer2)
                .blendMode(.screen)
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
}
