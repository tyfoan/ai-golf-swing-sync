//
//  HomeView.swift
//  golf-sync-swing
//
//  Compare tab: date-grouped swing selection for side-by-side comparison.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SwingVideo.createdAt, order: .reverse) private var videos: [SwingVideo]

    @State private var selectedSwings: [SwingSelection] = []
    @State private var navigationPath = NavigationPath()
    @State private var showPaywall = false
    @State private var hasKickedSeeder = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                header

                if userVideos.isEmpty && proVideos.isEmpty {
                    ContentUnavailableView(
                        "No Swings Yet",
                        systemImage: "figure.golf",
                        description: Text("Record or import a video to get started")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    swingPickerScroll
                    bottomCTA
                }
            }
            .background(Color.sandLight)
            .preferredColorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { clearButton }
            }
            .navigationDestination(for: SwingVideo.self) { video in
                SingleVideoPlayerView(video: video)
            }
            .navigationDestination(for: ComparisonDestination.self) { dest in
                ComparisonView(
                    video1: dest.video1, video2: dest.video2,
                    swing1: dest.swing1, swing2: dest.swing2
                )
            }
            .fullScreenCover(isPresented: $showPaywall) {
                AppPaywallView(source: .featureGate, onDismiss: { showPaywall = false })
            }
            .task { kickSeederIfNeeded() }
        }
    }

    /// Seeding lives here, not on the launch path: on a first launch it copies 19 bundled
    /// clips (~59 MB) and decodes a thumbnail per clip, and doing that during onboarding
    /// contended with the camera's first bring-up on disk and mediaserverd. The pro library
    /// is only needed once this tab is seen; `@Query` streams the pros in as they land.
    /// A plain call, not `Task.detached`: the seeder runs its own I/O in `@concurrent`
    /// helpers — a detached hop would only bounce straight back to the main actor for
    /// the SwiftData work.
    private func kickSeederIfNeeded() {
        guard !hasKickedSeeder else { return }
        hasKickedSeeder = true
        ProSwingSeeder.seedIfNeeded(container: modelContext.container)
    }

    private var swingPickerScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !proVideos.isEmpty {
                    ProSwingsCarouselView(
                        videos: proVideos,
                        selectedSwings: selectedSwings,
                        onTap: toggleSwingSelection
                    )
                }
                if !userVideos.isEmpty {
                    Text("MY SWINGS")
                        .font(.headline).fontWeight(.bold)
                        .foregroundStyle(Color.charcoal)
                        .padding(.horizontal)
                    SwingSelectionListContent(
                        groups: groupedUserVideos,
                        selectedSwings: selectedSwings,
                        onSwingTap: toggleSwingSelection
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Header

private extension HomeView {
    var header: some View {
        VStack(spacing: 8) {
            Text("Compare Swings")
                .font(.largeTitle).fontWeight(.bold)
                .foregroundStyle(Color.pineGreen)
            Text("Select 2 swings to compare side-by-side.")
                .font(.subheadline).foregroundStyle(Color.charcoal.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.top)
        .padding(.horizontal)
    }
}

// MARK: - Bottom CTA

private extension HomeView {
    @ViewBuilder
    var bottomCTA: some View {
        if selectedSwings.count == 2 {
            compareButton
        } else if selectedSwings.count == 1 {
            Text("Select one more swing to compare")
                .font(.subheadline).foregroundStyle(Color.charcoal.opacity(0.6))
                .padding()
        }
    }

    var compareButton: some View {
        Button { startComparison() } label: {
            Text("Compare 2 Swings")
                .font(.headline).fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.appTeal)
                .clipShape(RoundedRectangle(cornerRadius: 28))
        }
        .padding()
    }

    @ViewBuilder
    var clearButton: some View {
        if !selectedSwings.isEmpty {
            Button("Clear") {
                withAnimation { selectedSwings.removeAll() }
            }
        }
    }
}

// MARK: - Selection Logic

private extension HomeView {
    func toggleSwingSelection(_ swing: SwingMarker, in video: SwingVideo) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let idx = selectedSwings.firstIndex(where: { $0.swingId == swing.id }) {
                selectedSwings.remove(at: idx)
            } else if selectedSwings.count < 2 {
                selectedSwings.append(SwingSelection(from: swing, videoId: video.id))
            }
        }
    }

    func startComparison() {
        guard selectedSwings.count == 2 else { return }

        let sel1 = selectedSwings[0]
        let sel2 = selectedSwings[1]

        guard let v1 = videos.first(where: { $0.id == sel1.videoId }),
              let v2 = videos.first(where: { $0.id == sel2.videoId }) else { return }

        if (v1.isPro || v2.isPro) && !FeatureAccess.isPremiumUser {
            Analytics.shared.track(.featureGateHit(feature: .proSwingLibrary))
            showPaywall = true
            return
        }

        navigationPath.append(ComparisonDestination(
            video1: v1, video2: v2,
            swing1: sel1.swingTimeRange, swing2: sel2.swingTimeRange
        ))
        selectedSwings.removeAll()
    }
}

// MARK: - Grouping

private extension HomeView {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    var proVideos: [SwingVideo] {
        videos.filter { $0.isPro && !$0.swings.isEmpty }
    }

    var userVideos: [SwingVideo] {
        videos.filter { !$0.isPro }
    }

    var groupedUserVideos: [VideoDateGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: userVideos) {
            calendar.startOfDay(for: $0.createdAt)
        }

        return groups
            .map { VideoDateGroup(
                date: Self.dayFormatter.string(from: $0.key),
                sortDate: $0.key,
                videos: $0.value
            ) }
            .sorted { $0.sortDate > $1.sortDate }
    }
}

// MARK: - Supporting Types

struct SwingSelection: Hashable {
    let videoId: UUID
    let swingId: UUID
    let swingTimeRange: SwingTimeRange

    init(from swing: SwingMarker, videoId: UUID) {
        self.videoId = videoId
        self.swingId = swing.id
        self.swingTimeRange = SwingTimeRange(
            startTime: swing.startTime,
            contactTime: swing.contactTime,
            endTime: swing.endTime
        )
    }
}

struct VideoDateGroup: Identifiable {
    let date: String
    let sortDate: Date
    let videos: [SwingVideo]

    var id: String { date }
}

struct ComparisonDestination: Hashable {
    let video1: SwingVideo
    let video2: SwingVideo
    let swing1: SwingTimeRange
    let swing2: SwingTimeRange
}

#Preview {
    HomeView()
        .modelContainer(for: [SwingVideo.self, ComparisonSession.self], inMemory: true)
}
