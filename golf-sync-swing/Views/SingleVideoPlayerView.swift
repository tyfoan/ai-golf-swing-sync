//
//  SingleVideoPlayerView.swift
//  golf-sync-swing
//
//  Video playback with swing detection and marking.
//  Delegates swing UI to SwingDetectionPanel.
//

import SwiftUI
import SwiftData

struct SingleVideoPlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var video: SwingVideo

    @State private var viewModel: VideoPlayerViewModel?
    @State private var showSwingEditor = false
    @State private var editingSwing: SwingMarker?
    @State private var selectedSwingId: UUID?

    // Auto-detection state
    @State private var isAnalyzing = false
    @State private var analysisProgress: Float = 0
    @State private var analysisError: String?
    @State private var showAnalysisResult = false
    @State private var lastDetectionResults: [SwingDetectionResult] = []
    @State private var analysisStatus: String = ""

    private let syncEngine = VideoSyncEngine()

    var body: some View {
        VStack(spacing: 0) {
            if let vm = viewModel {
                videoPlayerSection(vm: vm)
                controlsSection(vm: vm)
                Divider().padding(.top, 12)
                SwingDetectionPanel(
                    video: video,
                    selectedSwingId: selectedSwingId,
                    isAnalyzing: isAnalyzing,
                    analysisProgress: analysisProgress,
                    analysisStatus: analysisStatus,
                    onAutoDetect: { runAutoDetection() },
                    onManualAdd: { editingSwing = nil; showSwingEditor = true },
                    onSwingTap: { swing in
                        selectedSwingId = swing.id
                        vm.seek(to: swing.startTime)
                        vm.play()
                    },
                    onSwingEdit: { swing in
                        editingSwing = swing
                        showSwingEditor = true
                    }
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // TODO: Export functionality
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear { viewModel = VideoPlayerViewModel(video: video) }
        .onDisappear { viewModel?.pause() }
        .sheet(isPresented: $showSwingEditor) { swingEditorSheet }
        .alert("Analysis Complete", isPresented: $showAnalysisResult) {
            Button("OK") { }
        } message: {
            analysisResultMessage
        }
        .alert("Analysis Error", isPresented: .init(
            get: { analysisError != nil },
            set: { if !$0 { analysisError = nil } }
        )) {
            Button("OK") { analysisError = nil }
        } message: {
            Text(analysisError ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func videoPlayerSection(vm: VideoPlayerViewModel) -> some View {
        VideoPlayerView(player: vm.player)
            .aspectRatio(16/9, contentMode: .fit)
            .background(Color.black)
            .onTapGesture { vm.togglePlayPause() }
    }

    @ViewBuilder
    private func controlsSection(vm: VideoPlayerViewModel) -> some View {
        VStack(spacing: 12) {
            TimelineSlider(
                viewModel: vm,
                swings: video.swings,
                onSwingTap: { swing in
                    selectedSwingId = swing.id
                    vm.seek(to: swing.startTime)
                    vm.play()
                }
            )
            PlaybackControlsView(viewModel: vm)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var analysisResultMessage: some View {
        let valid = lastDetectionResults.filter { $0.hasValidDetection }
        if valid.isEmpty {
            Text("Could not detect swing. Try adding markers manually.")
        } else if valid.count == 1, let result = valid.first {
            let impact = result.impactTime.map { String(format: "%.2fs", $0) } ?? "n/a"
            Text("Impact: \(impact)\nConfidence: \(Int(result.impactConfidence * 100))%")
        } else {
            Text("Detected \(valid.count) swings")
        }
    }

    @ViewBuilder
    private var swingEditorSheet: some View {
        let deleteAction: (() -> Void)? = editingSwing != nil ? { deleteCurrentSwing() } : nil
        SwingEditorSheet(
            video: video,
            existingSwing: editingSwing,
            onSave: saveSwing,
            onCancel: { showSwingEditor = false; editingSwing = nil },
            onDelete: deleteAction
        )
        .presentationDetents([.large])
    }

    // MARK: - Actions

    private func runAutoDetection() {
        isAnalyzing = true
        analysisProgress = 0
        analysisStatus = "Analyzing with Action Classifier..."

        Task {
            do {
                let results = try await syncEngine.analyzeAllSwings(
                    for: video, model: .actionClassifier
                ) { progress in
                    Task { @MainActor in analysisProgress = progress }
                }

                await MainActor.run {
                    lastDetectionResults = results
                    let autoDetected = video.swings.filter { $0.isAutoDetected }
                    for swing in autoDetected {
                        video.swings.removeAll { $0.id == swing.id }
                        modelContext.delete(swing)
                    }
                    for result in results where result.hasValidDetection {
                        let swing = SwingMarker(from: result)
                        swing.video = video
                        video.swings.append(swing)
                        modelContext.insert(swing)
                    }
                    isAnalyzing = false
                    showAnalysisResult = true
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    analysisError = error.localizedDescription
                }
            }
        }
    }

    private func saveSwing(start: TimeInterval, contact: TimeInterval, end: TimeInterval) {
        if let existing = editingSwing {
            existing.startTime = start
            existing.contactTime = contact
            existing.endTime = end
            existing.isAutoDetected = false
        } else {
            let swing = SwingMarker(startTime: start, contactTime: contact, endTime: end)
            swing.video = video
            video.swings.append(swing)
            modelContext.insert(swing)
        }
        showSwingEditor = false
        editingSwing = nil
    }

    private func deleteCurrentSwing() {
        guard let swing = editingSwing else { return }
        let swingId = swing.id
        video.swings.removeAll { (s: SwingMarker) -> Bool in s.id == swingId }
        modelContext.delete(swing)
        showSwingEditor = false
        editingSwing = nil
    }
}
