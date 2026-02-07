//
//  HomeView.swift
//  golf-sync-swing
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SwingVideo.createdAt, order: .reverse) private var videos: [SwingVideo]

    @State private var showVideoPicker = false
    @State private var selectedVideos: Set<UUID> = []
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Instructions when videos exist
                if !videos.isEmpty && selectedVideos.isEmpty {
                    Text("Tap videos to select for comparison, or tap play to view")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                VideoLibraryView(
                    videos: videos,
                    selectedVideos: selectedVideos,
                    onVideoSelect: toggleSelection,
                    onVideoPlay: playVideo,
                    onVideoDelete: deleteVideo
                )

                // Bottom bar
                bottomBar
            }
            .navigationTitle("Golf Sync Swing")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showVideoPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    if !selectedVideos.isEmpty {
                        Button("Clear") {
                            withAnimation {
                                selectedVideos.removeAll()
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showVideoPicker) {
                VideoPickerView(isPresented: $showVideoPicker) { url in
                    importVideo(from: url)
                }
            }
            .navigationDestination(for: SwingVideo.self) { video in
                SingleVideoPlayerView(video: video)
            }
            .navigationDestination(for: ComparisonDestination.self) { destination in
                ComparisonView(video1: destination.video1, video2: destination.video2)
            }
        }
    }

    private var bottomBar: some View {
        Group {
            if selectedVideos.count == 2 {
                Button {
                    startComparison()
                } label: {
                    Text("Compare Videos")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .padding()
            } else if selectedVideos.count == 1 {
                Text("Select one more video to compare")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private func playVideo(_ video: SwingVideo) {
        navigationPath.append(video)
    }

    private func toggleSelection(_ video: SwingVideo) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedVideos.contains(video.id) {
                selectedVideos.remove(video.id)
            } else {
                if selectedVideos.count < 2 {
                    selectedVideos.insert(video.id)
                }
            }
        }
    }

    private func startComparison() {
        let selectedVideosList = videos.filter { selectedVideos.contains($0.id) }
        guard selectedVideosList.count == 2 else { return }

        let destination = ComparisonDestination(
            video1: selectedVideosList[0],
            video2: selectedVideosList[1]
        )
        navigationPath.append(destination)
        selectedVideos.removeAll()
    }

    private func importVideo(from url: URL) {
        Task {
            do {
                try await VideoImportService().importVideo(from: url, into: modelContext)
            } catch {
                print("Error importing video: \(error)")
            }
        }
    }

    private func deleteVideo(_ video: SwingVideo) {
        VideoStorageService.shared.deleteVideo(at: video.localURL)
        modelContext.delete(video)
    }
}

struct ComparisonDestination: Hashable {
    let video1: SwingVideo
    let video2: SwingVideo
}

#Preview {
    HomeView()
        .modelContainer(for: [SwingVideo.self, ComparisonSession.self], inMemory: true)
}
