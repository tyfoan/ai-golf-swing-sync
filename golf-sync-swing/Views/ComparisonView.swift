//
//  ComparisonView.swift
//  golf-sync-swing
//

import SwiftUI

struct ComparisonView: View {
    let video1: SwingVideo
    let video2: SwingVideo

    @State private var viewModel: ComparisonViewModel?
    @State private var showExportSheet = false
    @State private var exportProgress: Float = 0
    @State private var isExporting = false

    // Auto-sync state
    @State private var isAutoSyncing = false
    @State private var autoSyncProgress: Float = 0
    @State private var autoSyncStatus: String = ""
    @State private var syncResult: SyncResult?
    @State private var syncError: String?

    private let syncEngine = VideoSyncEngine()

    var body: some View {
        VStack(spacing: 0) {
            if let viewModel = viewModel {
                // Side-by-side videos (vertical stack)
                GeometryReader { geometry in
                    VStack(spacing: 1) {
                        VideoPlayerView(player: viewModel.effectivePlayer1)
                            .frame(height: geometry.size.height / 2)
                            .background(Color.black)
                            .onTapGesture {
                                viewModel.togglePlayPause()
                            }

                        VideoPlayerView(player: viewModel.effectivePlayer2)
                            .frame(height: geometry.size.height / 2)
                            .background(Color.black)
                            .onTapGesture {
                                viewModel.togglePlayPause()
                            }
                    }
                    .gesture(
                        DragGesture()
                            .onEnded { value in
                                // Horizontal drag adjusts sync offset
                                let offsetDelta = Double(value.translation.width) / 100.0
                                viewModel.adjustSyncOffset(by: offsetDelta)
                            }
                    )
                }

                // Controls
                VStack(spacing: 12) {
                    // Sync controls
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
                    Button {
                        viewModel.swapVideos()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .onAppear {
            viewModel = ComparisonViewModel(video1: video1, video2: video2)
        }
        .onDisappear {
            viewModel?.pause()
        }
        .sheet(isPresented: $showExportSheet) {
            if let viewModel = viewModel {
                ExportProgressView(
                    viewModel: viewModel,
                    isExporting: $isExporting,
                    progress: $exportProgress,
                    onDismiss: { showExportSheet = false }
                )
            }
        }
        .alert("Sync Error", isPresented: .init(
            get: { syncError != nil },
            set: { if !$0 { syncError = nil } }
        )) {
            Button("OK") { syncError = nil }
        } message: {
            Text(syncError ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func syncControlsSection(viewModel: ComparisonViewModel) -> some View {
        VStack(spacing: 8) {
            if isAutoSyncing {
                // Progress view
                VStack(spacing: 4) {
                    ProgressView(value: Double(autoSyncProgress))
                        .progressViewStyle(.linear)

                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(autoSyncStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(autoSyncProgress * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                HStack {
                    // Sync offset display
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("Sync:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%+.2fs", viewModel.syncOffset))
                                .font(.caption)
                                .fontWeight(.medium)
                                .monospacedDigit()

                            if let result = syncResult, result.isHighConfidence {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }

                        if let result = syncResult {
                            Text(result.description)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text("Drag horizontally to adjust")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    // Auto-sync button
                    Button {
                        runAutoSync(viewModel: viewModel)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text("Auto-Sync")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .cornerRadius(8)
                    }

                    // Reset button
                    if viewModel.syncOffset != 0 {
                        Button {
                            viewModel.setSyncOffset(0)
                            syncResult = nil
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func runAutoSync(viewModel: ComparisonViewModel) {
        isAutoSyncing = true
        autoSyncProgress = 0
        autoSyncStatus = "Starting..."

        Task {
            do {
                let result = try await syncEngine.calculateSyncOffset(
                    video1: video1,
                    video2: video2
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

// MARK: - Comparison Timeline Slider

struct ComparisonTimelineSlider: View {
    @Bindable var viewModel: ComparisonViewModel
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * viewModel.progress, height: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 16 : 12, height: isDragging ? 16 : 12)
                        .shadow(radius: 2)
                        .offset(x: geometry.size.width * viewModel.progress - (isDragging ? 8 : 6))
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            viewModel.seekToProgress(progress)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
            .frame(height: 20)

            HStack {
                Text(formatTime(viewModel.currentTime))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formatTime(viewModel.totalDuration))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let hundredths = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
    }
}

// MARK: - Comparison Controls

struct ComparisonControlsView: View {
    @Bindable var viewModel: ComparisonViewModel
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Button {
                viewModel.stepFrame(forward: false)
            } label: {
                Image(systemName: "backward.frame.fill")
                    .font(.title2)
            }

            Button {
                viewModel.togglePlayPause()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
            }

            Button {
                viewModel.stepFrame(forward: true)
            } label: {
                Image(systemName: "forward.frame.fill")
                    .font(.title2)
            }

            Spacer()

            // Speed picker
            Menu {
                ForEach(ComparisonViewModel.playbackRates, id: \.self) { rate in
                    Button {
                        viewModel.setPlaybackRate(rate)
                    } label: {
                        HStack {
                            Text(formatRate(rate))
                            if rate == viewModel.playbackRate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(formatRate(viewModel.playbackRate))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }

            Button(action: onExport) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
            }
        }
        .foregroundStyle(.primary)
    }

    private func formatRate(_ rate: Float) -> String {
        if rate == 1.0 {
            return "1x"
        } else if rate >= 0.5 {
            return String(format: "%.1fx", rate)
        } else {
            return String(format: "%.3fx", rate)
        }
    }
}
