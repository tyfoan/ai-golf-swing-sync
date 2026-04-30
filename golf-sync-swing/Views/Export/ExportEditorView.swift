//
//  ExportEditorView.swift
//  golf-sync-swing
//

import SwiftUI

struct ExportEditorView: View {
    @State var viewModel: ExportEditorViewModel
    let onCancel: () -> Void
    let onExport: (VideoLayoutConfig) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                topBar
                canvas
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { viewModel.setupPlayers() }
        .onDisappear { viewModel.cleanup() }
    }

    private var topBar: some View {
        HStack {
            Button { onCancel() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            Spacer()
            Text(viewModel.aspectRatio.displayName)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var canvas: some View {
        if let p1 = viewModel.player1, let p2 = viewModel.player2 {
            EditorCanvas(
                aspectRatio: viewModel.aspectRatio,
                player1: p1,
                player2: p2,
                transform1: $viewModel.transforms[0],
                transform2: $viewModel.transforms[1]
            )
        } else {
            Spacer()
            ProgressView().tint(.white)
            Spacer()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Text("Pinch to zoom · Drag to position · Tap speaker to mute")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Button { onExport(viewModel.buildLayoutConfig()) } label: {
                Text("Export")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
