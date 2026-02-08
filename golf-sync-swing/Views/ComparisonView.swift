//
//  ComparisonView.swift
//  golf-sync-swing
//
//  Dark immersive side-by-side video comparison with auto-sync.
//

import SwiftUI

struct ComparisonView: View {
    let video1: SwingVideo
    let video2: SwingVideo
    var contactTime1: TimeInterval?
    var contactTime2: TimeInterval?

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ComparisonViewModel?
    @State private var showExportSheet = false
    @State private var exportProgress: Float = 0
    @State private var isExporting = false
    @State private var showDoneSheet = false
    @State private var isAutoSyncing = false
    @State private var autoSyncProgress: Float = 0
    @State private var autoSyncStatus: String = ""
    @State private var syncResult: SyncResult?
    @State private var syncError: String?
    @State private var showSyncConfirmation = false
    private let syncEngine = VideoSyncEngine()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let viewModel = viewModel {
                contentStack(viewModel: viewModel)
            } else {
                ProgressView().tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { onViewAppear() }
        .onDisappear { viewModel?.pause() }
        .sheet(isPresented: $showExportSheet) { exportSheet }
        .confirmationDialog("Done", isPresented: $showDoneSheet, titleVisibility: .hidden) {
            Button("Export Video") { showExportSheet = true }
            Button("Done") { dismiss() }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Sync Error", isPresented: .init(
            get: { syncError != nil }, set: { if !$0 { syncError = nil } }
        )) {
            Button("OK") { syncError = nil }
        } message: {
            Text(syncError ?? "Unknown error")
        }
    }
}

// MARK: - Content Layout

private extension ComparisonView {
    func contentStack(viewModel: ComparisonViewModel) -> some View {
        VStack(spacing: 0) {
            topBar(viewModel: viewModel)
            ComparisonVideoAreaView(
                viewModel: viewModel, isAutoSyncing: isAutoSyncing,
                autoSyncStatus: autoSyncStatus, showSyncConfirmation: showSyncConfirmation
            )
            controlsPanel(viewModel: viewModel)
        }
    }

    func topBar(viewModel: ComparisonViewModel) -> some View {
        HStack {
            circleButton(icon: "xmark") { showDoneSheet = true }
            Spacer()
            circleButton(icon: "arrow.left.arrow.right") { viewModel.swapVideos() }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    func circleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body).fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 36, height: 36)
                .background(Color(.systemGray5))
                .clipShape(Circle())
        }
    }
}

// MARK: - Controls Panel

private extension ComparisonView {
    func controlsPanel(viewModel: ComparisonViewModel) -> some View {
        VStack(spacing: 12) {
            ComparisonTimelineSlider(viewModel: viewModel)
            SyncOffsetStrip(viewModel: viewModel)
            modePicker(viewModel: viewModel)
            premiumControls(viewModel: viewModel)
            ComparisonControlsView(viewModel: viewModel)
            doneButton
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    func modePicker(viewModel: ComparisonViewModel) -> some View {
        Menu {
            ForEach(ComparisonMode.allCases) { mode in
                modeMenuItem(mode: mode, viewModel: viewModel)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.comparisonMode.iconName)
                    .font(.caption)
                Text(viewModel.comparisonMode.rawValue)
                    .font(.subheadline).fontWeight(.medium)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .foregroundStyle(Color.appTeal)
        }
    }

    @ViewBuilder
    func modeMenuItem(mode: ComparisonMode, viewModel: ComparisonViewModel) -> some View {
        if mode.isAvailable {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.comparisonMode = mode
                }
            } label: {
                HStack {
                    Label(mode.rawValue, systemImage: mode.iconName)
                    if mode == viewModel.comparisonMode {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } else {
            Button { } label: {
                Label("\(mode.rawValue) (Pro)", systemImage: "lock.fill")
            }
            .disabled(true)
        }
    }

    @ViewBuilder
    func premiumControls(viewModel: ComparisonViewModel) -> some View {
        if viewModel.comparisonMode == .onionSkin {
            onionSkinSlider(viewModel: viewModel)
        }
        if viewModel.tempoDescription != nil {
            tempoSyncToggle(viewModel: viewModel)
        }
    }

    func onionSkinSlider(viewModel: ComparisonViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
            Slider(value: Binding(
                get: { viewModel.onionSkinOpacity },
                set: { viewModel.onionSkinOpacity = $0 }
            ), in: 0.1...0.9)
            .tint(Color.appTeal)
            Image(systemName: "circle.righthalf.filled")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    func tempoSyncToggle(viewModel: ComparisonViewModel) -> some View {
        Button {
            viewModel.toggleTempoSync()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: viewModel.tempoSyncEnabled ? "metronome.fill" : "metronome")
                    .font(.caption)
                Text(viewModel.tempoDescription ?? "")
                    .font(.caption2)
            }
            .foregroundStyle(viewModel.tempoSyncEnabled ? Color.appTeal : .white.opacity(0.5))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
        }
    }

    var doneButton: some View {
        Button { showDoneSheet = true } label: {
            Text("DONE")
                .font(.headline).fontWeight(.bold).foregroundStyle(.white)
                .frame(width: 200, height: 48)
                .background(Color.appTeal)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    var exportSheet: some View {
        if let viewModel = viewModel {
            ExportProgressView(
                viewModel: viewModel, isExporting: $isExporting,
                progress: $exportProgress, onDismiss: { showExportSheet = false }
            )
        }
    }
}

// MARK: - Auto Sync

private extension ComparisonView {
    func onViewAppear() {
        let vm = ComparisonViewModel(video1: video1, video2: video2)
        viewModel = vm

        // Quick initial seek using ActionClassifier times (instant, ~250ms accuracy)
        if let c1 = contactTime1, let c2 = contactTime2 {
            vm.setSyncOffset(c1 - c2)
            vm.seekToImpact(contactTime1: c1, contactTime2: c2)
        }

        // Always refine with SwingNet for precise frame-level impact alignment
        runSwingNetSync(viewModel: vm)
    }

    func runSwingNetSync(viewModel: ComparisonViewModel) {
        isAutoSyncing = true
        autoSyncProgress = 0
        autoSyncStatus = "Refining sync..."
        Task {
            do {
                let result = try await syncEngine.calculateSyncOffset(
                    video1: video1, video2: video2,
                    approximateContact1: contactTime1,
                    approximateContact2: contactTime2
                ) { progress, status in
                    Task { @MainActor in
                        autoSyncProgress = progress
                        autoSyncStatus = status
                    }
                }
                await MainActor.run {
                    syncResult = result
                    viewModel.applySyncResult(result)
                    isAutoSyncing = false
                    showSyncConfirmationBriefly()
                }
            } catch {
                await MainActor.run {
                    isAutoSyncing = false
                    syncError = error.localizedDescription
                }
            }
        }
    }

    func showSyncConfirmationBriefly() {
        withAnimation { showSyncConfirmation = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { withAnimation { showSyncConfirmation = false } }
        }
    }
}
