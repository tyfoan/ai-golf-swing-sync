//
//  ComparisonControlsView.swift
//  golf-sync-swing
//
//  Dark circular playback controls for the comparison view.
//

import SwiftUI

struct ComparisonControlsView: View {
    @Bindable var viewModel: ComparisonViewModel

    var body: some View {
        HStack(spacing: 0) {
            transportControls
            Spacer()
            speedPill
        }
    }

    // MARK: - Transport

    private var transportControls: some View {
        HStack(spacing: 16) {
            frameStepButton(forward: false)
            playPauseButton
            frameStepButton(forward: true)
        }
    }

    private func frameStepButton(forward: Bool) -> some View {
        Button { viewModel.stepFrame(forward: forward) } label: {
            Image(systemName: forward ? "forward.frame.fill" : "backward.frame.fill")
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
        .accessibilityLabel(forward ? Text("Next frame") : Text("Previous frame"))
    }

    private var playPauseButton: some View {
        Button { viewModel.togglePlayPause() } label: {
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
        }
        .accessibilityLabel(viewModel.isPlaying ? Text("Pause") : Text("Play"))
    }

    // MARK: - Speed Pill

    private var speedPill: some View {
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
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityLabel("Playback speed")
    }

    // MARK: - Formatting

    private func formatRate(_ rate: Float) -> String {
        if rate == 1.0 { return String(localized: "1x", comment: "Playback speed pill at normal speed") }
        let digits = rate >= 0.5 ? 1 : 3
        let value = Double(rate).formatted(.number.precision(.fractionLength(digits)))
        return String(localized: "\(value)x", comment: "Playback speed pill, e.g. \"0.5x\" or \"0.125x\"")
    }
}
