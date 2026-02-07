//
//  ComparisonControlsView.swift
//  golf-sync-swing
//
//  Playback controls for the comparison view.
//

import SwiftUI

struct ComparisonControlsView: View {
    @Bindable var viewModel: ComparisonViewModel
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Button { viewModel.stepFrame(forward: false) } label: {
                Image(systemName: "backward.frame.fill").font(.title2)
            }

            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill").font(.title)
            }

            Button { viewModel.stepFrame(forward: true) } label: {
                Image(systemName: "forward.frame.fill").font(.title2)
            }

            Spacer()

            Menu {
                ForEach(ComparisonViewModel.playbackRates, id: \.self) { rate in
                    Button {
                        viewModel.setPlaybackRate(rate)
                    } label: {
                        HStack {
                            Text(formatRate(rate))
                            if rate == viewModel.playbackRate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(formatRate(viewModel.playbackRate))
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }

            Button(action: onExport) {
                Image(systemName: "square.and.arrow.up").font(.title2)
            }
        }
        .foregroundStyle(.primary)
    }

    private func formatRate(_ rate: Float) -> String {
        if rate == 1.0 { return "1x" }
        else if rate >= 0.5 { return String(format: "%.1fx", rate) }
        else { return String(format: "%.3fx", rate) }
    }
}
