//
//  ComparisonStage.swift
//  golf-sync-swing
//
//  The video area of the comparison screen: a pair of panes for the parallel modes,
//  placed by the mode's PairArrangement, or a single pane for sequential, labelled with
//  whichever swing is playing.
//

import SwiftUI

struct ComparisonStage: View {
    let viewModel: ComparisonViewModel
    let atlas: ComparisonAtlas
    let labels: [PaneLabel]

    var body: some View {
        if let arrangement = viewModel.comparisonMode.pairArrangement {
            PairStage(viewModel: viewModel, atlas: atlas, labels: labels, arrangement: arrangement)
        } else {
            ComparisonPane(
                player: viewModel.player,
                cutout: atlas.cutout(forTrack: viewModel.sequentialSegment),
                label: labels[viewModel.sequentialVideo]
            )
        }
    }
}

/// Both swings at once. Panes are keyed by track, so a swap or a mode switch moves the
/// same two panes rather than rebuilding them.
struct PairStage: View {
    let viewModel: ComparisonViewModel
    let atlas: ComparisonAtlas
    let labels: [PaneLabel]
    let arrangement: PairArrangement

    var body: some View {
        arrangement.layout {
            ForEach(Array(viewModel.trackOrder.enumerated()), id: \.element) { position, track in
                pane(track: track, position: position)
            }
            StageSwapButton(symbol: arrangement.swapSymbol) {
                withAnimation(.snappy(duration: 0.35)) { viewModel.swapVideos() }
            }
        }
    }

    private func pane(track: Int, position: Int) -> some View {
        ComparisonPane(
            player: viewModel.player,
            cutout: atlas.cutout(forTrack: track),
            label: labels[track],
            style: arrangement.style(ofPaneAt: position, overlayOpacity: viewModel.stackedOpacity)
        )
        .layoutValue(key: PaneAspect.self, value: atlas.aspectRatio(ofTrack: track))
    }
}

/// Holds the stage's place, in the panes' shape, while the composition is built — or,
/// without the spinner, while the export sheet has the player.
struct StagePlaceholder: View {
    var isLoading = true

    var body: some View {
        RoundedRectangle(cornerRadius: StageCard.cornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.05))
            .overlay {
                if isLoading { ProgressView() }
            }
    }
}
