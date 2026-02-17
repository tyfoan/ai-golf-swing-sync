//
//  ManualPlaybackSynchronizer.swift
//  golf-sync-swing
//
//  Drift-correction-based synchronization for dual AVPlayer playback.
//
//  The reference player (player1) is authoritative. The follower (player2)
//  is periodically checked against its expected position (t1 - offset) and
//  corrected when drift exceeds the threshold.
//
//  This is the correct approach for offset-based sync where two players
//  show different videos aligned at a common event (impact).
//

import AVFoundation

final class ManualPlaybackSynchronizer: PlaybackSynchronizing {

    private weak var follower: AVPlayer?
    private var offset: TimeInterval = 0
    private var followerBounds: SwingTimeRange?

    private let maxDrift: TimeInterval

    init(maxDrift: TimeInterval = 0.04) {
        self.maxDrift = maxDrift
    }

    // MARK: - PlaybackSynchronizing

    func start(
        reference: AVPlayer,
        follower: AVPlayer,
        offset: TimeInterval,
        followerBounds: SwingTimeRange
    ) {
        self.follower = follower
        self.offset = offset
        self.followerBounds = followerBounds
    }

    func updateOffset(_ offset: TimeInterval) {
        self.offset = offset
    }

    func correctDriftIfNeeded(referenceTime: TimeInterval) {
        guard let follower, let bounds = followerBounds else { return }
        let expected = max(bounds.startTime, referenceTime - offset)
        let actual = CMTimeGetSeconds(follower.currentTime())
        let drift = abs(actual - expected)

        guard drift > maxDrift else { return }
        seekFollower(to: expected)
    }

    func resync(referenceTime: TimeInterval) {
        guard let bounds = followerBounds else { return }
        let expected = max(bounds.startTime, referenceTime - offset)
        seekFollower(to: expected)
    }

    func stop() {
        follower = nil
        followerBounds = nil
    }

    // MARK: - Private

    private func seekFollower(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        follower?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
