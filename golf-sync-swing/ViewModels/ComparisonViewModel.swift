//
//  ComparisonViewModel.swift
//  golf-sync-swing
//
//  Orchestrates dual-player playback within swing bounds.
//
//  Three modes (all use a baseline of impact-frame sync):
//  - sideBySide: both videos visible, manual synchronizer keeps them aligned.
//  - stacked: both visible at full canvas, blended at stackedOpacity.
//  - sequential: one player plays at a time, advances on loop.
//

import Foundation
import AVFoundation
import os

@MainActor
@Observable
final class ComparisonViewModel {
    let player1: AVPlayer
    let player2: AVPlayer
    let video1: SwingVideo
    let video2: SwingVideo
    let swing1: SwingTimeRange
    let swing2: SwingTimeRange

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var playbackRate: Float = 1.0
    var syncOffset: TimeInterval = 0
    var comparisonMode: ComparisonMode = .sideBySide {
        didSet { onModeChanged() }
    }
    var stackedOpacity: CGFloat = 0.5
    var currentSequentialSwing: Int = 0   // 0 = swing1 playing, 1 = swing2 playing

    nonisolated(unsafe) private var timeObserver1: Any?
    nonisolated(unsafe) private var timeObserver2: Any?
    private(set) var isSwapped = false
    private var loopInProgress = false
    private let synchronizer: PlaybackSynchronizing

    static let playbackRates: [Float] = [0.125, 0.25, 0.5, 1.0]

    // MARK: - Display ordering (swap is purely visual)

    /// Players in render order. First entry renders left/top/back, second renders
    /// right/bottom/front. `isSwapped` flips the pair; sync logic stays on
    /// player1 (reference) and player2 (follower).
    var orderedPlayers: [AVPlayer] {
        isSwapped ? [player2, player1] : [player1, player2]
    }

    /// Timeline duration is always the reference swing (player1).
    var totalDuration: TimeInterval { swing1.duration }

    /// Time relative to reference swing start, for display.
    var displayTime: TimeInterval { max(0, currentTime - swing1.startTime) }

    // MARK: - Init

    init(
        video1: SwingVideo,
        video2: SwingVideo,
        swing1: SwingTimeRange,
        swing2: SwingTimeRange,
        synchronizer: PlaybackSynchronizing = ManualPlaybackSynchronizer()
    ) {
        self.video1 = video1
        self.video2 = video2
        self.swing1 = swing1
        self.swing2 = swing2
        self.player1 = AVPlayer(url: video1.validLocalURL ?? video1.localURL)
        self.player2 = AVPlayer(url: video2.validLocalURL ?? video2.localURL)
        // Keep playback locked to the requested rate even when the player's
        // buffer is briefly thin — otherwise heavier follower decodes (HEVC
        // user clips contending with the H.264 pro clip) silently pause
        // themselves and look like frozen playback to the user.
        self.player1.automaticallyWaitsToMinimizeStalling = false
        self.player2.automaticallyWaitsToMinimizeStalling = false
        self.synchronizer = synchronizer
        if swing1.contactTime > 0 && swing2.contactTime > 0 {
            self.syncOffset = swing1.contactTime - swing2.contactTime
        } else {
            self.syncOffset = 0
            AppLogger.detection.warning("ComparisonViewModel: missing contact time(s) — synced playback will be unaligned")
        }

        setupTimeObservers()
        seekToSwingStarts()
    }

    deinit {
        if let obs = timeObserver1 { player1.removeTimeObserver(obs) }
        if let obs = timeObserver2 { player2.removeTimeObserver(obs) }
    }

    func cleanup() {
        player1.pause()
        player1.replaceCurrentItem(with: nil)
        player2.pause()
        player2.replaceCurrentItem(with: nil)
        synchronizer.stop()
        if let obs = timeObserver1 { player1.removeTimeObserver(obs); timeObserver1 = nil }
        if let obs = timeObserver2 { player2.removeTimeObserver(obs); timeObserver2 = nil }
        isPlaying = false
    }

    // MARK: - Time Observers

    private func setupTimeObservers() {
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)

        timeObserver1 = player1.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            self?.onPlayer1Tick(CMTimeGetSeconds(time))
        }

        timeObserver2 = player2.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            self?.onPlayer2Tick(CMTimeGetSeconds(time))
        }
    }

    private func onPlayer1Tick(_ time: TimeInterval) {
        currentTime = time
        loopIfNeeded(player: player1, swing: swing1, isReference: true)

        guard usesSynchronizer, isPlaying else { return }
        synchronizer.correctDriftIfNeeded(referenceTime: time)
    }

    private func onPlayer2Tick(_ time: TimeInterval) {
        loopIfNeeded(player: player2, swing: swing2, isReference: false)
    }

    /// Sequential mode runs only one player at a time, no synchronizer.
    /// Both other modes use the manual synchronizer.
    private var usesSynchronizer: Bool {
        comparisonMode != .sequential
    }

    // MARK: - Looping

    private func loopIfNeeded(player: AVPlayer, swing: SwingTimeRange, isReference: Bool) {
        guard isPlaying, !loopInProgress else { return }
        let time = CMTimeGetSeconds(player.currentTime())
        guard time >= swing.endTime - 0.01 else { return }

        if comparisonMode == .sequential {
            advanceSequentialSwing()
            return
        }
        // sideBySide / stacked: only the reference player triggers a joint loop.
        guard isReference else { return }
        loopToTimelineStart()
    }

    private func loopToTimelineStart() {
        loopInProgress = true
        let cmTime = CMTime(seconds: swing1.startTime, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.04, preferredTimescale: 600)
        player1.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            DispatchQueue.main.async { self?.loopInProgress = false }
        }
        currentTime = swing1.startTime
        synchronizer.resync(referenceTime: swing1.startTime)
    }

    private func advanceSequentialSwing() {
        currentSequentialSwing = (currentSequentialSwing + 1) % 2
        if currentSequentialSwing == 0 {
            seekPlayer(player1, to: swing1.startTime)
            player1.rate = playbackRate
            player2.pause()
        } else {
            seekPlayer(player2, to: swing2.startTime)
            player2.rate = playbackRate
            player1.pause()
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        if usesSynchronizer {
            startSynchronizer()
            synchronizer.resync(referenceTime: currentTime)
            player1.rate = playbackRate
            player2.rate = playbackRate
        } else {
            playSequential()
        }
        isPlaying = true
    }

    private func playSequential() {
        if currentSequentialSwing == 0 {
            player1.rate = playbackRate
            player2.pause()
        } else {
            player2.rate = playbackRate
            player1.pause()
        }
    }

    func pause() {
        player1.pause()
        player2.pause()
        isPlaying = false
        loopInProgress = false
    }

    func seek(to time: TimeInterval) {
        guard time.isFinite, swing1.startTime.isFinite, swing1.endTime.isFinite else { return }
        let clamped = clamp(time, within: swing1)
        seekPlayer(player1, to: clamped)

        if usesSynchronizer {
            synchronizer.resync(referenceTime: clamped)
        } else {
            seekPlayer2Proportionally(clamped)
        }
        currentTime = clamped
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        guard isPlaying else { return }
        if usesSynchronizer {
            player1.rate = rate
            player2.rate = rate
        } else {
            playSequential()
        }
    }

    func stepFrame(forward: Bool) {
        let step = 1.0 / video1.fps
        let newTime = forward
            ? min(currentTime + step, swing1.endTime)
            : max(currentTime - step, swing1.startTime)
        seek(to: newTime)
    }

    /// Swap is purely visual: flips which panel renders which player. The
    /// synchronizer still treats player1 as reference and player2 as follower,
    /// so playback state, sync offset, and timeline are untouched.
    func swapVideos() {
        guard comparisonMode != .sequential else { return }
        isSwapped.toggle()
    }

    // MARK: - Progress

    var progress: Double {
        guard swing1.duration > 0 else { return 0 }
        return max(0, min(1, (currentTime - swing1.startTime) / swing1.duration))
    }

    func seekToProgress(_ progress: Double) {
        let time = swing1.startTime + progress * swing1.duration
        seek(to: time)
    }

    // MARK: - Private Helpers

    private func seekPlayer(_ player: AVPlayer, to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func seekToSwingStarts() {
        seekPlayer(player1, to: swing1.startTime)
        seekPlayer(player2, to: swing2.startTime)
        currentTime = swing1.startTime
    }

    private func seekPlayer2Proportionally(_ referenceTime: TimeInterval) {
        let fraction = swing1.duration > 0
            ? (referenceTime - swing1.startTime) / swing1.duration
            : 0
        let time2 = swing2.startTime + fraction * swing2.duration
        seekPlayer(player2, to: clamp(time2, within: swing2))
    }

    private func onModeChanged() {
        guard usesSynchronizer else {
            synchronizer.stop()
            // Reset sequential state on mode entry
            currentSequentialSwing = 0
            return
        }
        startSynchronizer()
        synchronizer.resync(referenceTime: currentTime)
    }

    private func startSynchronizer() {
        synchronizer.start(
            reference: player1, follower: player2,
            offset: syncOffset, followerBounds: swing2
        )
    }

    private func clamp(_ time: TimeInterval, within swing: SwingTimeRange) -> TimeInterval {
        max(swing.startTime, min(swing.endTime, time))
    }
}
