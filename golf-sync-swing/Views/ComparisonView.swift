//
//  ComparisonView.swift
//  golf-sync-swing
//
//  The comparison screen: two impact-aligned swings on a stage, the mode switcher
//  above, playback below. It opens in whichever arrangement shows both swings biggest
//  (ComparisonArrangementAdvisor).
//

import SwiftUI

struct ComparisonView: View {
    let video1: SwingVideo
    let video2: SwingVideo
    let swing1: SwingTimeRange
    let swing2: SwingTimeRange

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ComparisonViewModel?
    @State private var recordedPlayback = false
    @State private var showExportSheet = false
    @State private var showPaywall = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            StageBackdrop()
            if let viewModel = viewModel {
                contentStack(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await openIfNeeded() }
        // Pause only — never tear the player down here. `onDisappear` also fires when this
        // view merely presents the export sheet or the paywall, and `openIfNeeded` is
        // guarded on `viewModel == nil`, so a teardown could never be undone: the
        // comparison screen came back permanently black. The time observer is released in
        // `ComparisonViewModel.deinit`, which is the correct place for it.
        .onDisappear { viewModel?.pause() }
        .onChange(of: viewModel?.currentTime) { _, time in
            guard !recordedPlayback, let time, time > 0, viewModel?.buildError == nil else { return }
            recordedPlayback = true
            FirstComparisonAccess().recordPlayback(video1, video2)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { viewModel?.pause() }
        }
        .sheet(isPresented: $showExportSheet, onDismiss: { viewModel?.reclaimAfterExport() }) { exportSheet }
        .fullScreenCover(isPresented: $showPaywall) {
            AppPaywallView(source: .featureGate, onDismiss: { showPaywall = false })
        }
    }
}

// MARK: - Content Layout

private extension ComparisonView {
    func contentStack(viewModel: ComparisonViewModel) -> some View {
        VStack(spacing: 12) {
            ComparisonTopBar(
                mode: viewModel.comparisonMode,
                // The editor needs the built composition: it previews on it, and which
                // swings have sound decides the default mutes.
                canExport: viewModel.atlas != nil && viewModel.buildError == nil,
                onClose: { dismiss() },
                onSelectMode: select,
                onExport: presentExport
            )
            stageArea(viewModel: viewModel)
            ComparisonControlsPanel(viewModel: viewModel)
                .disabled(viewModel.buildError != nil)
        }
    }

    func stageArea(viewModel: ComparisonViewModel) -> some View {
        ZStack {
            stage(viewModel: viewModel)
            if let message = viewModel.buildError {
                ComparisonBuildErrorView(message: message, onRetry: viewModel.retryBuild)
            }
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.togglePlayPause() }
    }

    /// While the export sheet is up its editor shows these swings on the same player,
    /// so the stage steps aside rather than keep its own layers attached underneath.
    @ViewBuilder
    func stage(viewModel: ComparisonViewModel) -> some View {
        if showExportSheet {
            StagePlaceholder(isLoading: false)
        } else if let atlas = viewModel.atlas {
            ComparisonStage(viewModel: viewModel, atlas: atlas, labels: paneLabels)
        } else {
            StagePlaceholder()
        }
    }

    var paneLabels: [PaneLabel] {
        [PaneLabel(video: video1), PaneLabel(video: video2)]
    }
}

// MARK: - Actions

private extension ComparisonView {
    func select(_ mode: ComparisonMode) {
        guard let viewModel else { return }
        guard mode.isAvailable else { return offerUpgrade(for: mode) }
        withAnimation(.snappy(duration: 0.35)) { viewModel.select(mode) }
    }

    func offerUpgrade(for mode: ComparisonMode) {
        if let feature = mode.premiumFeature {
            Analytics.shared.track(.featureGateHit(feature: feature))
        }
        showPaywall = true
    }

    func presentExport() {
        showExportSheet = true
    }

    @ViewBuilder
    var exportSheet: some View {
        if let viewModel = viewModel,
           let url1 = video1.validLocalURL,
           let url2 = video2.validLocalURL {
            let swapped = viewModel.isSwapped
            ExportFlowCoordinator(
                video1URL: swapped ? url2 : url1,
                video2URL: swapped ? url1 : url2,
                swing1: swapped ? swing2 : swing1,
                swing2: swapped ? swing1 : swing2,
                syncOffset: swapped ? -viewModel.syncOffset : viewModel.syncOffset,
                comparisonViewModel: viewModel,
                labels: swapped ? paneLabels.reversed() : paneLabels,
                onDismiss: { showExportSheet = false }
            )
        } else {
            Text("Videos unavailable")
                .padding()
                .onAppear { showExportSheet = false }
        }
    }
}

// MARK: - Setup

private extension ComparisonView {
    /// Reads how the two clips are shaped first, so the comparison opens — and reports
    /// `comparison_opened` — in the arrangement it will actually show.
    func openIfNeeded() async {
        guard viewModel == nil else { return }
        let mode = await ComparisonArrangementAdvisor().preferredMode(for: [video1, video2])
        guard viewModel == nil, !Task.isCancelled else { return }
        let vm = ComparisonViewModel(
            video1: video1, video2: video2,
            swing1: swing1, swing2: swing2,
            initialMode: mode
        )
        viewModel = vm
        Analytics.shared.track(.comparisonOpened(mode: vm.comparisonMode))
        vm.play()
    }
}
