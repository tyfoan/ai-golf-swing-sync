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

    private let seekTolerance: TimeInterval
    private let correctionThreshold: TimeInterval

    private var seekToken: UInt = 0
    private var inFlightSeek: UInt?

    /// `seekTolerance` is the per-seek precision passed to `AVPlayer.seek`. A
    /// tighter value forces the player to decode from the nearest I-frame —
    /// cheap for the bundled H.264 pro clips but punitive on user-recorded
    /// HEVC, which causes the follower to visibly stutter. 100 ms gives
    /// AVFoundation room to land on a friendly frame while still staying
    /// well below `correctionThreshold` so we don't induce re-seek loops.
    init(seekTolerance: TimeInterval = 0.1, correctionThreshold: TimeInterval = 0.15) {
        self.seekTolerance = seekTolerance
        self.correctionThreshold = correctionThreshold
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

    func correctDriftIfNeeded(referenceTime: TimeInterval) {
        guard let follower, let bounds = followerBounds, inFlightSeek == nil else { return }
        let expected = clampToBounds(referenceTime - offset, bounds: bounds)
        let actual = CMTimeGetSeconds(follower.currentTime())
        let drift = abs(actual - expected)

        guard drift > correctionThreshold else { return }
        seekFollower(to: expected)
    }

    func resync(referenceTime: TimeInterval) {
        guard let bounds = followerBounds else { return }
        let expected = clampToBounds(referenceTime - offset, bounds: bounds)
        seekFollower(to: expected)
    }

    func stop() {
        follower = nil
        followerBounds = nil
        inFlightSeek = nil
    }

    // MARK: - Private

    private func clampToBounds(_ time: TimeInterval, bounds: SwingTimeRange) -> TimeInterval {
        max(bounds.startTime, min(bounds.endTime, time))
    }

    private func seekFollower(to time: TimeInterval) {
        guard let follower else { return }
        seekToken &+= 1
        let myToken = seekToken
        inFlightSeek = myToken
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let tolerance = CMTime(seconds: seekTolerance, preferredTimescale: 600)
        follower.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.inFlightSeek == myToken else { return }
                self.inFlightSeek = nil
            }
        }
    }
}
