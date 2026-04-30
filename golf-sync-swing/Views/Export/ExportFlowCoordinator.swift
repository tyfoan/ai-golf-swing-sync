//
//  ExportFlowCoordinator.swift
//  golf-sync-swing
//
//  Hosts the 3-step export flow: aspect picker → editor → progress.
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

    @State private var step: Step = .picker
    @State private var selectedAspect: ExportAspectRatio?
    @State private var pendingConfig: VideoLayoutConfig?
    @State private var isExporting = false
    @State private var progress: Float = 0

    enum Step: Equatable {
        case picker
        case editor(ExportAspectRatio)
        case progress(VideoLayoutConfig)
    }

    var body: some View {
        Group {
            switch step {
            case .picker:
                AspectRatioPickerView(
                    onSelect: { aspect in
                        selectedAspect = aspect
                        step = .editor(aspect)
                    },
                    onCancel: onDismiss
                )
            case .editor(let aspect):
                editor(aspect: aspect)
            case .progress(let config):
                progressSheet(config: config)
            }
        }
    }

    private func editor(aspect: ExportAspectRatio) -> some View {
        let vm = ExportEditorViewModel(
            aspectRatio: aspect,
            video1URL: video1URL,
            video2URL: video2URL,
            swing1: swing1,
            swing2: swing2,
            syncOffset: syncOffset
        )
        return ExportEditorView(
            viewModel: vm,
            onCancel: { step = .picker },
            onExport: { config in
                pendingConfig = config
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
