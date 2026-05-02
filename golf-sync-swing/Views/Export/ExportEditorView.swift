//
//  ExportEditorView.swift
//  golf-sync-swing
//

import SwiftUI

struct ExportEditorView: View {
    @State var viewModel: ExportEditorViewModel
    let onCancel: () -> Void
    let onExport: (VideoLayoutConfig) -> Void

    /// Three primary aspect options shown inline at the top of the editor.
    private let primaryAspects: [ExportAspectRatio] = [.sideBySide, .tikTokVertical, .square]

    var body: some View {
        VStack(spacing: 0) {
            header
            aspectToggle
            canvas
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Spacer()
            exportButton
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { viewModel.setupPlayers() }
        .onDisappear { viewModel.cleanup() }
    }

    private var header: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            Spacer()
            Text("Export").foregroundStyle(.white).font(.headline)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var aspectToggle: some View {
        Picker("", selection: Binding(
            get: { viewModel.aspectRatio },
            set: { viewModel.aspectRatio = $0 }
        )) {
            ForEach(primaryAspects) { aspect in
                Text(aspect.displayName).tag(aspect)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var canvas: some View {
        if let p1 = viewModel.player1, let p2 = viewModel.player2 {
            EditorCanvas(
                aspectRatio: viewModel.aspectRatio,
                mode: viewModel.mode,
                stackedOpacity: viewModel.stackedOpacity,
                player1: p1,
                player2: p2,
                transform1: Binding(
                    get: { viewModel.transforms[0] },
                    set: { viewModel.transforms[0] = $0 }
                ),
                transform2: Binding(
                    get: { viewModel.transforms[1] },
                    set: { viewModel.transforms[1] = $0 }
                ),
                sequentialEditIndex: Binding(
                    get: { viewModel.currentSequentialEditSwing },
                    set: { viewModel.currentSequentialEditSwing = $0 }
                )
            )
        } else {
            ProgressView().tint(.white)
        }
    }

    private var exportButton: some View {
        Button {
            onExport(viewModel.buildLayoutConfig())
        } label: {
            Text("Export")
                .font(.headline).fontWeight(.bold).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.appTeal)
                .clipShape(RoundedRectangle(cornerRadius: 26))
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
    }
}
