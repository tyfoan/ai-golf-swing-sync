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

    private func editor() -> some View {
        let defaultAspect = comparisonViewModel.comparisonMode.defaultExportAspect
        let vm = ExportEditorViewModel(
            aspectRatio: defaultAspect,
            mode: comparisonViewModel.comparisonMode,
            stackedOpacity: comparisonViewModel.stackedOpacity,
            video1URL: video1URL,
            video2URL: video2URL,
            swing1: swing1,
            swing2: swing2,
            syncOffset: syncOffset
        )
        return ExportEditorView(
            viewModel: vm,
            onCancel: onDismiss,
            onExport: { config in
                step = .progress(config)
            }
        )
    }

    private func progressSheet(config: VideoLayoutConfig) -> some View {
        ExportProgressView(
            viewModel: comparisonViewModel,
            layoutConfig: config,
            swingTrim: (swing1, swing2),
            isExporting: $isExporting,
            progress: $progress,
            onDismiss: onDismiss
        )
    }
}
