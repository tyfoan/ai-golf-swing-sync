//
//  ExportEditorControls.swift
//  golf-sync-swing
//
//  Below the canvas: which swing to frame when they share the canvas, whose sound goes
//  into the file (only swings that have any — the pro swings are silent), and how
//  framing works.
//

import SwiftUI

struct ExportEditorControls: View {
    @Bindable var viewModel: ExportEditorViewModel

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.framesOneSwingAtATime {
                swingPicker
            }
            soundToggles
            Text("Pinch and drag to frame each swing", comment: "Hint under the export editor's canvas")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private var swingPicker: some View {
        Picker(selection: $viewModel.framedPosition) {
            ForEach(viewModel.labels.indices, id: \.self) { position in
                Text(verbatim: viewModel.labels[position].caption).tag(position)
            }
        } label: {
            Text("Swing to frame", comment: "Accessibility label of the export editor's picker for the overlaid swing being framed")
        }
        .pickerStyle(.segmented)
    }

    private var soundToggles: some View {
        HStack(spacing: 10) {
            ForEach(audiblePositions, id: \.self) { position in
                SoundToggleChip(
                    label: viewModel.labels[position],
                    isMuted: $viewModel.transforms[position].isMuted
                )
            }
        }
    }

    private var audiblePositions: [Int] {
        viewModel.labels.indices.filter(viewModel.hasSound(atPosition:))
    }
}
