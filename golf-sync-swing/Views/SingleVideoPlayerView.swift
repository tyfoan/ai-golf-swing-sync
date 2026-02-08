//
//  SingleVideoPlayerView.swift
//  golf-sync-swing
//
//  Dark immersive video player with mode picker,
//  floating actions, and swing thumbnail strip.
//

import SwiftUI
import SwiftData

struct SingleVideoPlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var video: SwingVideo

    @State private var viewModel: VideoPlayerViewModel?
    @State private var playbackMode: VideoPlaybackMode = .swingsOnly
    @State private var selectedSwingId: UUID?
    @State private var showSwingEditor = false
    @State private var editingSwing: SwingMarker?
    @State private var detector = SwingAutoDetectionRunner()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            mainContent
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: handleAppear)
        .onDisappear { viewModel?.pause() }
        .sheet(isPresented: $showSwingEditor) { swingEditorSheet }
    }
}

// MARK: - Layout

private extension SingleVideoPlayerView {
    @ViewBuilder
    var mainContent: some View {
        if let vm = viewModel {
            VStack(spacing: 0) {
                PlayerTopBarView(
                    playbackMode: playbackMode,
                    onDismiss: { dismiss() },
                    onSwitchMode: switchMode
                )
                videoArea(vm: vm)
                controlsSection(vm: vm)
                swingsSection(vm: vm)
            }
        } else {
            ProgressView().tint(.white)
        }
    }

    func videoArea(vm: VideoPlayerViewModel) -> some View {
        ZStack {
            VideoPlayerView(player: vm.player)
                .background(Color.black)
                .onTapGesture { vm.togglePlayPause() }
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VideoFloatingActionsView(
                        isFavorite: selectedSwing?.isFavorite ?? false,
                        isMuted: vm.isMuted,
                        showFavorite: playbackMode == .swingsOnly,
                        onToggleFavorite: { selectedSwing?.isFavorite.toggle() },
                        onToggleMute: { vm.toggleMute() }
                    )
                }
                .padding(.trailing, 4)
            }
            AnalysisOverlayView(
                isAnalyzing: detector.isAnalyzing,
                progress: detector.progress,
                status: detector.status
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
    }

    func controlsSection(vm: VideoPlayerViewModel) -> some View {
        VStack(spacing: 6) {
            PlaybackControlsView(viewModel: vm)
            TimelineSlider(
                viewModel: vm,
                swings: video.swings,
                onSwingTap: { swing in selectSwing(swing, vm: vm) }
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    func swingsSection(vm: VideoPlayerViewModel) -> some View {
        if playbackMode == .swingsOnly {
            SwingDetectionPanel(
                video: video,
                selectedSwingId: selectedSwingId,
                isAnalyzing: detector.isAnalyzing,
                analysisProgress: detector.progress,
                analysisStatus: detector.status,
                onAddNew: { editingSwing = nil; showSwingEditor = true },
                onEditSelected: { editSelectedSwing() },
                onSwingTap: { swing in selectSwing(swing, vm: vm) }
            )
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    var swingEditorSheet: some View {
        SwingEditorSheet(
            video: video,
            existingSwing: editingSwing,
            onSave: saveSwing,
            onCancel: { showSwingEditor = false; editingSwing = nil },
            onDelete: editingSwing != nil ? { deleteCurrentSwing() } : nil
        )
        .presentationDetents([.large])
    }
}

// MARK: - Actions

private extension SingleVideoPlayerView {
    func handleAppear() {
        let vm = VideoPlayerViewModel(video: video)
        viewModel = vm
        playbackMode = video.swings.isEmpty ? .fullVideo : .swingsOnly

        // Always start playing so the user sees the video immediately
        vm.play()

        guard !video.hasBeenAnalyzed else { return }
        Task {
            let swings = await detector.analyze(video: video, context: modelContext)
            guard let first = swings.first else {
                playbackMode = .fullVideo
                return
            }
            playbackMode = .swingsOnly
            selectSwing(first, vm: vm)
        }
    }

    func switchMode(to mode: VideoPlaybackMode) {
        playbackMode = mode
        guard let vm = viewModel else { return }

        switch mode {
        case .swingsOnly:
            guard let first = video.swings.first else { return }
            selectSwing(first, vm: vm)
        case .fullVideo:
            vm.clearSwingBounds()
            selectedSwingId = nil
        }
    }

    func selectSwing(_ swing: SwingMarker, vm: VideoPlayerViewModel) {
        selectedSwingId = swing.id
        vm.playSwing(swing)
    }

    var selectedSwing: SwingMarker? {
        guard let id = selectedSwingId else { return nil }
        return video.swings.first { $0.id == id }
    }

    func editSelectedSwing() {
        editingSwing = selectedSwing
        showSwingEditor = true
    }

    func saveSwing(start: TimeInterval, contact: TimeInterval, end: TimeInterval) {
        if let existing = editingSwing {
            existing.updateTimes(start: start, contact: contact, end: end)
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

    func deleteCurrentSwing() {
        guard let swing = editingSwing else { return }
        video.swings.removeAll { $0.id == swing.id }
        modelContext.delete(swing)
        showSwingEditor = false
        editingSwing = nil
        selectedSwingId = video.swings.first?.id
    }
}

// MARK: - Playback Mode

enum VideoPlaybackMode: String, CaseIterable {
    case swingsOnly = "Swings Only"
    case fullVideo = "Full Video"
}
