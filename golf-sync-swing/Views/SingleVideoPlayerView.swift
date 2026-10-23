//
//  SingleVideoPlayerView.swift
//  golf-sync-swing
//
//  One recording on the cream stage, like the comparison: mode picker, the swing in a
//  dark card with floating actions, the shared transport, and the swing thumbnail strip.
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
    @State private var showExportSheet = false
    @State private var videoAspect: CGFloat?

    var body: some View {
        ZStack {
            StageBackdrop()
            mainContent
        }
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: handleAppear)
        .task(id: video.id) { videoAspect = await VideoDisplaySize.aspectRatio(of: video.validLocalURL) }
        // Pause only — never tear the player down here. `onDisappear` also fires when this
        // view merely presents the editor or export sheet, and `handleAppear` is guarded on
        // `viewModel == nil`, so a teardown would strand a dead player behind the sheet.
        // The time observer and player item are released in `VideoPlayerViewModel.deinit`,
        // which is the correct place for them.
        .onDisappear { viewModel?.pause() }
        .sheet(isPresented: $showSwingEditor) { swingEditorSheet }
        .sheet(isPresented: $showExportSheet) {
            SingleVideoExportSheet(
                video: video,
                mode: playbackMode,
                selectedSwing: selectedSwing,
                onDismiss: { showExportSheet = false }
            )
        }
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
                    onSwitchMode: switchMode,
                    onExport: { showExportSheet = true }
                )
                videoArea(vm: vm)
                controlsSection(vm: vm)
                swingsSection(vm: vm)
            }
        } else {
            ProgressView()
        }
    }

    func videoArea(vm: VideoPlayerViewModel) -> some View {
        SingleVideoCard(player: vm.player, aspectRatio: videoAspect) {
            VideoFloatingActionsView(
                isFavorite: selectedSwing?.isFavorite ?? false,
                isMuted: vm.isMuted,
                showFavorite: playbackMode == .swingsOnly,
                onToggleFavorite: { selectedSwing?.isFavorite.toggle() },
                onToggleMute: { vm.toggleMute() }
            )
            .padding(.trailing, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { vm.togglePlayPause() }
        // The card keeps the video's shape; the space around it stays the stage's.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    func controlsSection(vm: VideoPlayerViewModel) -> some View {
        VStack(spacing: 6) {
            TransportControlsView(model: vm)
            TimelineSlider(
                viewModel: vm,
                swings: video.swings,
                onSwingTap: { swing in selectSwing(swing, vm: vm) }
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    func swingsSection(vm: VideoPlayerViewModel) -> some View {
        SwingDetectionPanel(
            video: video,
            selectedSwingId: selectedSwingId,
            isAnalyzing: false,
            analysisProgress: 0,
            analysisStatus: "",
            onAddNew: { editingSwing = nil; showSwingEditor = true },
            onEditSelected: { editSelectedSwing() },
            onSwingTap: { swing in selectSwing(swing, vm: vm) }
        )
        .padding(.top, 6)
        .padding(.bottom, 16)
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
        guard viewModel == nil else { return }
        let vm = VideoPlayerViewModel(video: video)
        viewModel = vm

        let hasValidSwing = video.swings.contains { vm.isSwingValid($0) }
        playbackMode = hasValidSwing ? .swingsOnly : .fullVideo

        vm.play()

        guard let first = video.swings.first(where: { vm.isSwingValid($0) }) else { return }
        selectSwing(first, vm: vm)
    }

    func switchMode(to mode: VideoPlaybackMode) {
        playbackMode = mode
        guard let vm = viewModel else { return }

        switch mode {
        case .swingsOnly:
            guard let first = video.swings.first(where: { vm.isSwingValid($0) }) else { return }
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
            showSwingEditor = false
            editingSwing = nil
        } else {
            let swing = SwingMarker(startTime: start, contactTime: contact, endTime: end)
            swing.video = video
            video.swings.append(swing)
            modelContext.insert(swing)
            showSwingEditor = false
            editingSwing = nil
            playbackMode = .swingsOnly
            if let vm = viewModel { selectSwing(swing, vm: vm) }
        }
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

    var displayName: String {
        switch self {
        case .swingsOnly: return String(localized: "Swings Only", comment: "Playback mode showing detected swings only")
        case .fullVideo:  return String(localized: "Full Video", comment: "Playback mode showing the entire recorded video")
        }
    }
}
