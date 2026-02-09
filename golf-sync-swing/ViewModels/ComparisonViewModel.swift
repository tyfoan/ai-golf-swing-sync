//
//  ComparisonViewModel.swift
//  golf-sync-swing
//
//  Orchestrates dual-player playback within swing bounds.
//
//  Two modes:
//  - Side-by-side (free): Both videos loop their own swing independently.
//  - Synchronized (paid): Player1 is time reference; player2 follows
//    at (time - syncOffset) with periodic drift correction.
//

import Foundation
import AVFoundation

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
    var comparisonMode: ComparisonMode = .sideBySideSynced {
        didSet { onModeChanged() }
    }
    var onionSkinOpacity: Double = 0.5

    private var timeObserver1: Any?
    private var timeObserver2: Any?
    private var isSwapped = false

    private let maxDrift: TimeInterval = 0.04

    static let playbackRates: [Float] = [0.125, 0.25, 0.5, 1.0]

    // MARK: - Effective (swapped) accessors

    var effectivePlayer1: AVPlayer { isSwapped ? player2 : player1 }
    var effectivePlayer2: AVPlayer { isSwapped ? player1 : player2 }
    var effectiveSwing1: SwingTimeRange { isSwapped ? swing2 : swing1 }
    var effectiveSwing2: SwingTimeRange { isSwapped ? swing1 : swing2 }

    /// Timeline duration = reference swing duration.
    var totalDuration: TimeInterval { swing1.duration }

    /// Time relative to swing start, for display.
    var displayTime: TimeInterval { max(0, currentTime - swing1.startTime) }

    // MARK: - Init

    init(video1: SwingVideo, video2: SwingVideo, swing1: SwingTimeRange, swing2: SwingTimeRange) {
        self.video1 = video1
        self.video2 = video2
        self.swing1 = swing1
        self.swing2 = swing2
        self.player1 = AVPlayer(url: video1.localURL)
        self.player2 = AVPlayer(url: video2.localURL)
        self.syncOffset = swing1.contactTime - swing2.contactTime

        setupTimeObservers()
        seekToSwingStarts()
        play()
    }

    deinit {
        player1.pause()
        player2.pause()
        MainActor.assumeIsolated {
            if let obs = timeObserver1 { player1.removeTimeObserver(obs) }
            if let obs = timeObserver2 { player2.removeTimeObserver(obs) }
        }
    }

    // MARK: - Time Observers

    private func setupTimeObservers() {
        let interval = CMTime(seconds: 0.01, preferredTimescale: 600)

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

        guard comparisonMode.isSynchronized, isPlaying else { return }
        correctDriftIfNeeded()
    }

    private func onPlayer2Tick(_ time: TimeInterval) {
        loopIfNeeded(player: player2, swing: swing2, isReference: false)
    }

    // MARK: - Looping

    private func loopIfNeeded(player: AVPlayer, swing: SwingTimeRange, isReference: Bool) {
        guard isPlaying else { return }
        let time = CMTimeGetSeconds(player.currentTime())
        guard time >= swing.endTime - 0.01 else { return }

        guard comparisonMode.isSynchronized else {
            seekPlayer(player, to: swing.startTime)
            return
        }
        // In synced mode, only the reference player triggers a joint loop.
        guard isReference else { return }
        seekToSwingStarts()
    }

    // MARK: - Drift Correction (synced modes only)

    private func correctDriftIfNeeded() {
        let t1 = CMTimeGetSeconds(player1.currentTime())
        let expected2 = max(swing2.startTime, t1 - syncOffset)
        let actual2 = CMTimeGetSeconds(player2.currentTime())
        let drift = abs(actual2 - expected2)

        guard drift > maxDrift else { return }
        seekPlayer(player2, to: expected2)
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        if comparisonMode.isSynchronized {
            let expected2 = max(swing2.startTime, currentTime - syncOffset)
            seekPlayer(player2, to: expected2)
        }
        player1.rate = playbackRate
        player2.rate = playbackRate
        isPlaying = true
    }

    func pause() {
        player1.pause()
        player2.pause()
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        let clamped = clamp(time, within: swing1)
        seekPlayer(player1, to: clamped)

        if comparisonMode.isSynchronized {
            let expected2 = max(swing2.startTime, clamped - syncOffset)
            seekPlayer(player2, to: expected2)
        } else {
            // In one-by-one, also seek player2 proportionally within its swing
            let fraction = swing1.duration > 0
                ? (clamped - swing1.startTime) / swing1.duration
                : 0
            let time2 = swing2.startTime + fraction * swing2.duration
            seekPlayer(player2, to: clamp(time2, within: swing2))
        }
        currentTime = clamped
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        guard isPlaying else { return }
        player1.rate = rate
        player2.rate = rate
    }

    func stepFrame(forward: Bool) {
        let step = 1.0 / 30.0
        let newTime = forward
            ? min(currentTime + step, swing1.endTime)
            : max(currentTime - step, swing1.startTime)
        seek(to: newTime)
    }

    func swapVideos() {
        isSwapped.toggle()
    }

    // MARK: - Sync Offset (synced modes)

    func adjustSyncOffset(by delta: TimeInterval) {
        syncOffset += delta
        resyncPlayer2()
    }

    func setSyncOffset(_ offset: TimeInterval) {
        syncOffset = offset
        resyncPlayer2()
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

    private func resyncPlayer2() {
        let expected2 = max(swing2.startTime, currentTime - syncOffset)
        seekPlayer(player2, to: expected2)
    }

    private func onModeChanged() {
        guard comparisonMode.isSynchronized else { return }
        resyncPlayer2()
    }

    private func clamp(_ time: TimeInterval, within swing: SwingTimeRange) -> TimeInterval {
        max(swing.startTime, min(swing.endTime, time))
    }
}
