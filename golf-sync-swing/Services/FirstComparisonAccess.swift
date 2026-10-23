import Foundation

/// One user video may be compared with pro references for free and reopened later.
/// Only successful playback consumes the first-video allowance; missing media does not.
@MainActor
struct FirstComparisonAccess {
    private let defaults: UserDefaults
    private let videoKey = "activation.freeComparedVideoID"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var hasUsedFirstVideo: Bool { defaults.string(forKey: videoKey) != nil }

    func allows(_ first: SwingVideo, _ second: SwingVideo) -> Bool {
        guard let ownVideo = ownVideo(first, second) else { return false }
        guard let used = defaults.string(forKey: videoKey) else { return true }
        return used == ownVideo.id.uuidString
    }

    @discardableResult
    func recordPlayback(_ first: SwingVideo, _ second: SwingVideo) -> Bool {
        guard !FeatureAccess.isPremiumUser, !hasUsedFirstVideo,
              let ownVideo = ownVideo(first, second) else { return false }
        defaults.set(ownVideo.id.uuidString, forKey: videoKey)
        Analytics.shared.track(.firstProComparisonPlayed)
        return true
    }

    private func ownVideo(_ first: SwingVideo, _ second: SwingVideo) -> SwingVideo? {
        guard first.isPro != second.isPro else { return nil }
        return first.isPro ? second : first
    }
}
