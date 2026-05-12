//
//  PlaybackSynchronizer.swift
//  golf-sync-swing
//
//  Protocol for dual-player playback synchronization strategies.
//
//  Separates the sync mechanism from ComparisonViewModel, enabling
//  future strategies (e.g., Apple's AVPlaybackCoordinationMedium when
//  it supports time-offset coordination) without changing the view model.
//
//  NOTE: AVPlaybackCoordinationMedium (iOS 26) syncs players at the SAME
//  time position. Our use case requires offset-based sync (player2 = t1 - offset),
//  so we use ManualPlaybackSynchronizer with periodic drift correction.
//

import AVFoundation

protocol PlaybackSynchronizing: AnyObject {

    /// Begin synchronizing two players with a time offset.
    /// - Parameters:
    ///   - reference: The reference player (player1)
    ///   - follower: The follower player (player2)
    ///   - offset: Time offset (reference.contactTime - follower.contactTime)
    ///   - followerBounds: Follower's valid swing time range
    func start(
        reference: AVPlayer,
        follower: AVPlayer,
        offset: TimeInterval,
        followerBounds: SwingTimeRange
    )

    /// Correct follower drift relative to reference position.
    /// Called from the reference player's time observer.
    func correctDriftIfNeeded(referenceTime: TimeInterval)

    /// Resync follower to expected position immediately.
    func resync(referenceTime: TimeInterval)

    /// Stop synchronization and clean up resources.
    func stop()
}
