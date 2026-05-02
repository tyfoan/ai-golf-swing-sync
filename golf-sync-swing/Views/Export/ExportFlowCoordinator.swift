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
    @State private var pendingConfig: VideoLayoutConfig?
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
        let defaultAspect = defaultAspectFor(mode: comparisonViewModel.comparisonMode)
        let vm = ExportEditorViewModel(
            aspectRatio: defaultAspect,
            mode: comparisonViewModel.comparisonMode,
            stackedOpacity: CGFloat(comparisonViewModel.stackedOpacity),
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
                pendingConfig = config
                step = .progress(config)
            }
        )
    }

    /// Sequential and Stacked default to 9:16 (more natural full-canvas);
    /// Side-by-Side defaults to 16:9 (HSTACK).
    private func defaultAspectFor(mode: ComparisonMode) -> ExportAspectRatio {
        switch mode {
        case .sideBySide: return .sideBySide
        case .stacked, .sequential: return .tikTokVertical
        }
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
