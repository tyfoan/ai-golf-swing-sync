#if DEBUG
import SwiftUI
import SwiftData

/// Exercises the real SwiftUI comparison and AVFoundation playback in an offline preview.
/// It verifies service outcomes; it does not substitute for tapping the production navigation.
struct ActivationComparisonPreview: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var videos: [SwingVideo]

    private var first: SwingVideo? { videos.first { $0.id.uuidString.hasPrefix("11111111-") } }
    private var second: SwingVideo? { videos.first { $0.id.uuidString.hasPrefix("22222222-") } }
    private var pro: SwingVideo? { videos.first { $0.localURL.lastPathComponent == "tiger-woods-driver.mp4" && $0.isPro } }

    var body: some View {
        Group {
            if let first, let pro, let ownSwing = first.swings.first, let proSwing = pro.swings.first {
                ComparisonView(video1: first, video2: pro,
                    swing1: SwingSelection(from: ownSwing, videoId: first.id).swingTimeRange,
                    swing2: SwingSelection(from: proSwing, videoId: pro.id).swingTimeRange)
                    .task { await verifyPlayback(first: first, pro: pro) }
            } else {
                ProgressView("Preparing local comparison preview")
            }
        }
        .task { ProSwingSeeder.seedIfNeeded(container: modelContext.container) }
    }

    private func verifyPlayback(first: SwingVideo, pro: SwingVideo) async {
        for _ in 0..<200 {
            if FirstComparisonAccess().hasUsedFirstVideo { break }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        let access = FirstComparisonAccess()
        let checks = [
            "successful_playback_recorded": access.hasUsedFirstVideo,
            "first_video_can_reopen": access.allows(first, pro),
            "second_video_requires_upgrade": second.map { !access.allows($0, pro) } ?? false,
            "pro_only_is_not_free_allowance": !access.allows(pro, pro),
            "no_production_customer": !PurchaseService.shared.isConfigured,
            "no_premium_entitlement": !FeatureAccess.isPremiumUser
        ]
        let path = SwingVideo.documentsDirectory.appendingPathComponent("activation-preview-result.json")
        if let data = try? JSONEncoder().encode(checks) { try? data.write(to: path) }
        DeviceProbe.event("activation_preview_finished", checks.mapValues(String.init), ui: true)
    }
}
#endif
