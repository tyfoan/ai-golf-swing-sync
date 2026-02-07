//
//  ComparisonView.swift
//  golf-sync-swing
//
//  Side-by-side video comparison with auto-sync.
//  Sub-views: ComparisonTimelineSlider, ComparisonControlsView (in Components/).
//

import SwiftUI

struct ComparisonView: View {
    let video1: SwingVideo
    let video2: SwingVideo

    @State private var viewModel: ComparisonViewModel?
    @State private var showExportSheet = false
    @State private var exportProgress: Float = 0
    @State private var isExporting = false

    @State private var isAutoSyncing = false
    @State private var autoSyncProgress: Float = 0
    @State private var autoSyncStatus: String = ""
    @State private var syncResult: SyncResult?
    @State private var syncError: String?

    private let syncEngine = VideoSyncEngine()

    var body: some View {
        VStack(spacing: 0) {
            if let viewModel = viewModel {
                videoPlayersSection(viewModel: viewModel)

                VStack(spacing: 12) {
                    syncControlsSection(viewModel: viewModel)
                    ComparisonTimelineSlider(viewModel: viewModel)
                    ComparisonControlsView(viewModel: viewModel, onExport: { showExportSheet = true })
                }
                .padding()
                .background(Color(.systemBackground))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let viewModel = viewModel {
                    Button { viewModel.swapVideos() } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .onAppear { viewModel = ComparisonViewModel(video1: video1, video2: video2) }
        .onDisappear { viewModel?.pause() }
        .sheet(isPresented: $showExportSheet) {
            if let viewModel = viewModel {
                ExportProgressView(
                    viewModel: viewModel, isExporting: $isExporting,
                    progress: $exportProgress, onDismiss: { showExportSheet = false }
                )
            }
        }
        .alert("Sync Error", isPresented: .init(
            get: { syncError != nil }, set: { if !$0 { syncError = nil } }
        )) {
            Button("OK") { syncError = nil }
        } message: {
            Text(syncError ?? "Unknown error")
        }
    }

    // MARK: - Video Players

    @ViewBuilder
    private func videoPlayersSection(viewModel: ComparisonViewModel) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 1) {
                VideoPlayerView(player: viewModel.effectivePlayer1)
                    .frame(height: geometry.size.height / 2)
                    .background(Color.black)
                    .onTapGesture { viewModel.togglePlayPause() }

                VideoPlayerView(player: viewModel.effectivePlayer2)
                    .frame(height: geometry.size.height / 2)
                    .background(Color.black)
                    .onTapGesture { viewModel.togglePlayPause() }
            }
            .gesture(
                DragGesture().onEnded { value in
                    let offsetDelta = Double(value.translation.width) / 100.0
                    viewModel.adjustSyncOffset(by: offsetDelta)
                }
            )
        }
    }

    // MARK: - Sync Controls

    @ViewBuilder
    private func syncControlsSection(viewModel: ComparisonViewModel) -> some View {
        VStack(spacing: 8) {
            if isAutoSyncing {
                syncProgressView
            } else {
                syncStatusBar(viewModel: viewModel)
            }
        }
    }

    private var syncProgressView: some View {
        VStack(spacing: 4) {
            ProgressView(value: Double(autoSyncProgress)).progressViewStyle(.linear)
            HStack {
                ProgressView().scaleEffect(0.7)
                Text(autoSyncStatus).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(autoSyncProgress * 100))%")
                    .font(.caption).monospacedDigit().foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func syncStatusBar(viewModel: ComparisonViewModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Sync:").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%+.2fs", viewModel.syncOffset))
                        .font(.caption).fontWeight(.medium).monospacedDigit()
                    if let result = syncResult, result.isHighConfidence {
                        Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    }
                }
                Text(syncResult?.description ?? "Drag horizontally to adjust")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Spacer()

            Button { runAutoSync(viewModel: viewModel) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                    Text("Auto-Sync")
                }
                .font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.orange).cornerRadius(8)
            }

            if viewModel.syncOffset != 0 {
                Button {
                    viewModel.setSyncOffset(0)
                    syncResult = nil
                } label: {
                    Image(systemName: "arrow.counterclockwise").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Auto Sync

    private func runAutoSync(viewModel: ComparisonViewModel) {
        isAutoSyncing = true
        autoSyncProgress = 0
        autoSyncStatus = "Starting..."

        Task {
            do {
                let result = try await syncEngine.calculateSyncOffset(
                    video1: video1, video2: video2
                ) { progress, status in
                    Task { @MainActor in
                        autoSyncProgress = progress
                        autoSyncStatus = status
                    }
                }
                await MainActor.run {
                    syncResult = result
                    viewModel.setSyncOffset(result.offset)
                    isAutoSyncing = false
                }
            } catch {
                await MainActor.run {
                    isAutoSyncing = false
                    syncError = error.localizedDescription
                }
            }
        }
    }
}
