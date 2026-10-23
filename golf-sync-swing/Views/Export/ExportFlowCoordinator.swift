//
//  ExportFlowCoordinator.swift
//  golf-sync-swing
//
//  Hosts the 2-step export flow: editor → progress.
//  Aspect picking is inline in the editor.
//

import SwiftUI

struct ExportFlowCoordinator: View {
    let video1URL: URL
    let video2URL: URL
    let swing1: SwingTimeRange
    let swing2: SwingTimeRange
    let syncOffset: TimeInterval
    let comparisonViewModel: ComparisonViewModel
    /// Whose swing is which, in the same (swap-aware) order as the URLs.
    let labels: [PaneLabel]
    let onDismiss: () -> Void

    @State private var step: Step = .editor
    @State private var isExporting = false
    @State private var progress: Float = 0

    enum Step: Equatable {
        case editor
        case progress(VideoLayoutConfig)
    }

    var body: some View {
        Group {
            switch step {
            case .editor:
                editor()
            case .progress(let config):
                progressSheet(config: config)
            }
        }
    }

    /// The editor previews on the comparison's player; once the export renders, the
    /// comparison lets go of its decoders until the sheet is gone.
    private func editor() -> some View {
        ExportEditorView(
            viewModel: ExportEditorViewModel(comparison: comparisonViewModel, labels: labels),
            onCancel: onDismiss,
            onExport: { config in
                comparisonViewModel.releaseForExport()
                step = .progress(config)
            }
        )
    }

    private func progressSheet(config: VideoLayoutConfig) -> some View {
        // The URL/syncOffset/swing triple all arrive from `ComparisonView`
        // already swap-aware; passing them straight through keeps the
        // exporter inputs internally consistent regardless of swap state.
        ExportProgressView(
            video1URL: video1URL,
            video2URL: video2URL,
            syncOffset: syncOffset,
            layoutConfig: config,
            swingTrim: (swing1, swing2),
            isExporting: $isExporting,
            progress: $progress,
            onDismiss: onDismiss
        )
    }
}
