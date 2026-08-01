//
//  RecordingControlsView.swift
//  golf-sync-swing
//
//  Bottom controls for recording view: start/stop/save buttons and action bar.
//

import SwiftUI

struct RecordingControlsView: View {
    @Bindable var viewModel: RecordingViewModel

    /// Injected rather than read off the camera: the button's only job is to say whether it
    /// can be pressed, and the tab already knows.
    let isCameraReady: Bool

    var body: some View {
        VStack(spacing: 20) {
            if viewModel.state == .idle {
                startRecordingButton
            } else if viewModel.isRecording {
                stopRecordingButton
            } else if viewModel.isReviewing {
                reviewingButtons
            }
        }
        .padding(.bottom, 100)
    }

    // MARK: - Button Variants

    /// Disabled until the session is actually running. The countdown starts in place on this
    /// screen, and a countdown that ticks against a session still coming up would sit at "5"
    /// over a black preview — the wait belongs here, where there is a live preview and a
    /// positioning guide to look at.
    private var startRecordingButton: some View {
        Button(action: viewModel.startRecording) {
            startRecordingLabel
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isCameraReady ? Color.fairwayGreen : Color.fairwayGreen.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.fairwayGreen.opacity(0.35), radius: 12, y: 4)
        }
        .disabled(!isCameraReady)
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private var startRecordingLabel: some View {
        if isCameraReady {
            Text("Start Recording")
        } else {
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("Preparing camera…")
            }
        }
    }

    private var stopRecordingButton: some View {
        Button(action: viewModel.stopRecording) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 70, height: 70)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.flagRed)
                    .frame(width: 30, height: 30)
            }
        }
    }

    private var reviewingButtons: some View {
        HStack(spacing: 20) {
            Button(action: viewModel.deleteRecording) {
                Text("Delete")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.flagRed.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Button {
                Task { await viewModel.saveRecording() }
            } label: {
                Text(viewModel.swingCount > 0 ? "Save (\(viewModel.swingCount))" : "Save")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.fairwayGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(viewModel.state == .saving)
        }
        .padding(.horizontal, 40)
    }
}
