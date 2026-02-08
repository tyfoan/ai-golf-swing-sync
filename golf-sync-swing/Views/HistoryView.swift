//
//  HistoryView.swift
//  golf-sync-swing
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SwingVideo.createdAt, order: .reverse) private var videos: [SwingVideo]

    @State private var showVideoPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if videos.isEmpty {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "video.badge.plus",
                        description: Text("Import videos to start marking swings")
                    )
                } else {
                    List {
                        ForEach(videos) { video in
                            NavigationLink(destination: SingleVideoPlayerView(video: video)) {
                                VideoHistoryRow(video: video)
                            }
                        }
                        .onDelete(perform: deleteVideos)
                        .listRowBackground(Color.sandLight)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.sandLight)
            .preferredColorScheme(.light)
            .navigationTitle("Recordings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showVideoPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    if !videos.isEmpty {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showVideoPicker) {
                VideoPickerView(isPresented: $showVideoPicker) { url in
                    importVideo(from: url)
                }
            }
        }
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

    private func deleteVideos(at offsets: IndexSet) {
        for index in offsets {
            let video = videos[index]
            VideoStorageService.shared.deleteVideo(at: video.localURL)
            modelContext.delete(video)
        }
    }
}

struct VideoHistoryRow: View {
    let video: SwingVideo

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumbnailData = video.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.ivory)
                    .frame(width: 80, height: 60)
                    .overlay {
                        Image(systemName: "video.fill")
                            .foregroundStyle(.secondary)
                    }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDate(video.createdAt))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.pineGreen)

                HStack(spacing: 8) {
                    Label(formatDuration(video.duration), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label("\(video.swings.count) swing\(video.swings.count == 1 ? "" : "s")", systemImage: "figure.golf")
                        .font(.caption)
                        .foregroundColor(video.swings.isEmpty ? .secondary : .fairwayGreen)
                }
            }

            Spacer()

            // Swing count badge
            if !video.swings.isEmpty {
                Text("\(video.swings.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.fairwayGreen)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [SwingVideo.self, SwingMarker.self, ComparisonSession.self], inMemory: true)
}
