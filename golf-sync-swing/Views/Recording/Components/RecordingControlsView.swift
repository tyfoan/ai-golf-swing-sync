//
//  RecordingControlsView.swift
//  golf-sync-swing
//
//  Bottom controls for recording view: start/stop/save buttons and action bar.
//

import SwiftUI
import SwiftData

struct RecordingControlsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: RecordingViewModel

    var body: some View {
        VStack(spacing: 20) {
            if viewModel.isRecording {
                actionButtons
            }

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

    // MARK: - Action Buttons (during recording)

    private var actionButtons: some View {
        HStack(spacing: 24) {
            if viewModel.mainViewShowsReplay {
                Button(action: viewModel.showLiveCamera) {
                    Image(systemName: "video.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.blue.opacity(0.7))
                        .clipShape(Circle())
                }
            }

            SpeedButton(speed: viewModel.playbackSpeed)

            Button {
                if let index = viewModel.replayingSwingIndex ?? viewModel.detectedSwings.indices.last {
                    viewModel.toggleFavorite(at: index)
                }
            } label: {
                let isFavorite = viewModel.currentReplaySwing?.isFavorite
                    ?? viewModel.detectedSwings.last?.isFavorite ?? false
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundStyle(isFavorite ? .yellow : .white)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.5))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Button Variants

    private var startRecordingButton: some View {
        Button(action: viewModel.startRecording) {
            Text("Start Recording")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 40)
    }

    private var stopRecordingButton: some View {
        Button(action: viewModel.stopRecording) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 70, height: 70)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.red)
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
                    .background(Color.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Button {
                Task { _ = await viewModel.saveRecording(to: modelContext) }
            } label: {
                Text(viewModel.swingCount > 0 ? "Save (\(viewModel.swingCount))" : "Save")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(.horizontal, 40)
    }
}
