//
//  SingleVideoPlayerView.swift
//  golf-sync-swing
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
                swingsSection
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
        .onAppear {
            viewModel = VideoPlayerViewModel(video: video)
        }
        .onDisappear {
            viewModel?.pause()
        }
        .sheet(isPresented: $showSwingEditor) {
            swingEditorSheet
        }
        .alert("Analysis Complete", isPresented: $showAnalysisResult) {
            Button("OK") { }
        } message: {
            let valid = lastDetectionResults.filter { $0.hasValidDetection }
            if valid.isEmpty {
                Text("Model: SwingNet\nCould not detect swing. Try adding markers manually.")
            } else if valid.count == 1, let result = valid.first {
                let impact = result.impactTime.map { String(format: "%.2fs", $0) } ?? "n/a"
                Text(
                    "Model: SwingNet\nImpact: \(impact)\nConfidence: \(Int(result.impactConfidence * 100))%"
                )
            } else {
                Text("Model: SwingNet\nDetected \(valid.count) swings")
            }
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
            .onTapGesture {
                vm.togglePlayPause()
            }
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
    private var swingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            swingsHeader
            if isAnalyzing {
                analysisProgressView
            } else if video.swings.isEmpty {
                emptySwingsView
            } else {
                swingsList
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var swingsHeader: some View {
        HStack {
            Text("Swings")
                .font(.headline)

            Spacer()

            if !isAnalyzing {
                Button("AUTO-DETECT") {
                    runAutoDetection()
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
                .padding(.trailing, 8)

                Button("MANUAL") {
                    editingSwing = nil
                    showSwingEditor = true
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var analysisProgressView: some View {
        VStack(spacing: 12) {
            ProgressView(value: Double(analysisProgress))
                .progressViewStyle(.linear)

            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text(analysisStatus.isEmpty ? "Analyzing swing..." : analysisStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("\(Int(analysisProgress * 100))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var emptySwingsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("No swings detected")
                .font(.headline)

            Text("Tap AUTO-DETECT to analyze the video, or add markers manually.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if video.hasBeenAnalyzed {
                Text("Previously analyzed - no swing found")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var swingsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(video.swings.enumerated()), id: \.element.id) { (item: (offset: Int, element: SwingMarker)) in
                    swingRow(swing: item.element, index: item.offset)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func swingRow(swing: SwingMarker, index: Int) -> some View {
        VStack(spacing: 0) {
            SwingRowView(
                swing: swing,
                index: index,
                isSelected: selectedSwingId == swing.id,
                onTap: {
                    selectedSwingId = swing.id
                    viewModel?.seek(to: swing.startTime)
                    viewModel?.play()
                },
                onEdit: {
                    editingSwing = swing
                    showSwingEditor = true
                }
            )

            // Show confidence badge for auto-detected swings
            if swing.isAutoDetected {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .font(.caption2)
                    Text("Auto-detected • \(swing.confidenceDescription) confidence")
                        .font(.caption2)
                }
                .foregroundStyle(swing.detectionConfidence >= 0.7 ? .green : .orange)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var swingEditorSheet: some View {
        let deleteAction: (() -> Void)? = editingSwing != nil ? { deleteCurrentSwing() } : nil
        SwingEditorSheet(
            video: video,
            existingSwing: editingSwing,
            onSave: saveSwing,
            onCancel: {
                showSwingEditor = false
                editingSwing = nil
            },
            onDelete: deleteAction
        )
        .presentationDetents([.large])
    }

    // MARK: - Actions

    private func runAutoDetection() {
        isAnalyzing = true
        analysisProgress = 0
        analysisStatus = "Analyzing with SwingNet..."

        Task {
            do {
                let results = try await syncEngine.analyzeAllSwings(for: video) { progress in
                    Task { @MainActor in
                        analysisProgress = progress
                    }
                }

                await MainActor.run {
                    lastDetectionResults = results

                    // Remove previous auto-detected markers
                    let autoDetected = video.swings.filter { $0.isAutoDetected }
                    for swing in autoDetected {
                        video.swings.removeAll { $0.id == swing.id }
                        modelContext.delete(swing)
                    }

                    // Add new markers for each valid detection
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
            existing.isAutoDetected = false // Manual edit removes auto-detected flag
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
