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
        .navigationTitle("Swings Only")
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
            TimelineSlider(viewModel: vm)
            PlaybackControlsView(viewModel: vm)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var swingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            swingsHeader
            if video.swings.isEmpty {
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

            Button("EDIT MANUALLY") {
                editingSwing = nil
                showSwingEditor = true
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.accentColor)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var emptySwingsView: some View {
        VStack(spacing: 8) {
            Text("There are no swings in this recording.")
                .foregroundStyle(.secondary)
            Text("Swings are automatically detected, but it's not 100% accurate. Create a new swing by tapping 'Edit Manually'")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
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

    private func saveSwing(start: TimeInterval, contact: TimeInterval, end: TimeInterval) {
        if let existing = editingSwing {
            existing.startTime = start
            existing.contactTime = contact
            existing.endTime = end
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
