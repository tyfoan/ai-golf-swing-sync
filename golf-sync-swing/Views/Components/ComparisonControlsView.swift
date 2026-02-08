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
        HStack(spacing: 20) {
            speedPill
            Spacer()
            frameStepButton(forward: false)
            playPauseButton
            frameStepButton(forward: true)
            Spacer()
            poseToggle
        }
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
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Transport Buttons

    private func frameStepButton(forward: Bool) -> some View {
        Button { viewModel.stepFrame(forward: forward) } label: {
            Image(systemName: forward ? "forward.frame.fill" : "backward.frame.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color(.systemGray5))
                .clipShape(Circle())
        }
    }

    private var playPauseButton: some View {
        Button { viewModel.togglePlayPause() } label: {
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color(.systemGray5))
                .clipShape(Circle())
        }
    }

    // MARK: - Pose Toggle

    private var poseToggle: some View {
        let available = FeatureAccess.isUnlocked(.poseEstimation)
        return Button {
            guard available else { return }
            viewModel.showPoseOverlay.toggle()
        } label: {
            Image(systemName: "figure.stand")
                .font(.title2)
                .foregroundStyle(poseButtonTint(available: available))
                .frame(width: 48, height: 48)
                .background(Color(.systemGray5))
                .clipShape(Circle())
                .overlay(poseActiveBorder)
        }
        .disabled(!available)
    }

    private func poseButtonTint(available: Bool) -> Color {
        guard available else { return .white.opacity(0.3) }
        return viewModel.showPoseOverlay ? Color.appTeal : .white.opacity(0.6)
    }

    @ViewBuilder
    private var poseActiveBorder: some View {
        if viewModel.showPoseOverlay {
            Circle()
                .strokeBorder(Color.appTeal, lineWidth: 2)
        }
    }

    // MARK: - Formatting

    private func formatRate(_ rate: Float) -> String {
        rate == 1.0
            ? "1x"
            : (rate >= 0.5 ? String(format: "%.1fx", rate) : String(format: "%.3fx", rate))
    }
}
