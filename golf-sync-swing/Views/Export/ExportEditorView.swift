//
//  ExportEditorView.swift
//  golf-sync-swing
//
//  Frame the export: aspect ratio on top, the canvas as it will render, per-swing
//  sound below, and the Export button pinned to the bottom edge.
//

import SwiftUI

struct ExportEditorView: View {
    @State var viewModel: ExportEditorViewModel
    let onCancel: () -> Void
    let onExport: (VideoLayoutConfig) -> Void

    /// Three primary aspect options shown inline at the top of the editor.
    private let primaryAspects: [ExportAspectRatio] = [.sideBySide, .tikTokVertical, .square]

    var body: some View {
        VStack(spacing: 16) {
            header
            aspectPicker
            canvas
            ExportEditorControls(viewModel: viewModel)
        }
        .padding(.top, 12)
        .safeAreaInset(edge: .bottom) { exportButton }
        .background { StageBackdrop() }
        .preferredColorScheme(.light)
        .onAppear { viewModel.attach() }
        .onDisappear { viewModel.detach() }
    }

    private var header: some View {
        ZStack {
            Text("Export", comment: "Sheet header title for the export editor (noun — 'the Export screen', not an action button)")
                .font(.headline)
                .foregroundStyle(.primary)
            HStack {
                StageIconButton(symbol: "xmark", label: "Close", action: onCancel)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    private var aspectPicker: some View {
        Picker(selection: $viewModel.aspectRatio) {
            ForEach(primaryAspects) { aspect in
                Text(verbatim: aspect.ratioLabel)
                    .accessibilityLabel(aspect.displayName)
                    .tag(aspect)
            }
        } label: {
            Text("Aspect ratio", comment: "Accessibility label of the export editor's aspect ratio picker")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var canvas: some View {
        if let atlas = viewModel.comparison.atlas {
            EditorCanvas(viewModel: viewModel, atlas: atlas)
                .padding(.horizontal, 16)
                .animation(.snappy(duration: 0.3), value: viewModel.aspectRatio)
        } else {
            ProgressView()
                .frame(maxHeight: .infinity)
        }
    }

    private var exportButton: some View {
        Button {
            onExport(viewModel.buildLayoutConfig())
        } label: {
            Text("Export", comment: "Primary CTA button label that triggers the export action (verb — 'Export now / Save', not a noun title)")
                .font(.headline).fontWeight(.bold).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.appTeal, in: .capsule)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}
