//
//  ComparisonViewModel.swift
//  golf-sync-swing
//
//  Orchestrates dual-player synchronized playback.
//  Player1 is the time reference; player2 follows at (time - syncOffset).
//  A periodic re-sync corrects drift during playback.
//

import Foundation
import AVFoundation
import Combine

@Observable
final class ComparisonViewModel {
    let player1: AVPlayer
    let player2: AVPlayer
    let video1: SwingVideo
    let video2: SwingVideo

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var playbackRate: Float = 1.0
    var syncOffset: TimeInterval = 0
    var comparisonMode: ComparisonMode = .sideBySide
    var onionSkinOpacity: Double = 0.5
    var showPoseOverlay: Bool = false

    /// Tempo adjustment for video2 (1.0 = same speed, >1.0 = faster, <1.0 = slower)
    var video2TempoAdjustment: Float = 1.0

    /// Whether tempo sync is enabled
    var tempoSyncEnabled: Bool = false

    /// Description of tempo adjustment for UI
    var tempoDescription: String? {
        guard abs(video2TempoAdjustment - 1.0) > 0.05 else { return nil }
        let percent = Int(abs(video2TempoAdjustment - 1.0) * 100)
        return video2TempoAdjustment > 1.0
            ? "Video 2: +\(percent)% speed"
            : "Video 2: -\(percent)% speed"
    }

    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var isSwapped = false

    /// Drift threshold (seconds) before forcing a re-sync of player2
    private let maxDrift: TimeInterval = 0.04

    static let playbackRates: [Float] = [0.125, 0.25, 0.5, 1.0]

    var effectiveVideo1: SwingVideo { isSwapped ? video2 : video1 }
    var effectiveVideo2: SwingVideo { isSwapped ? video1 : video2 }
    var effectivePlayer1: AVPlayer { isSwapped ? player2 : player1 }
    var effectivePlayer2: AVPlayer { isSwapped ? player1 : player2 }

    var totalDuration: TimeInterval {
        max(video1.duration, video2.duration + syncOffset)
    }

    init(video1: SwingVideo, video2: SwingVideo) {
        self.video1 = video1
        self.video2 = video2
        self.player1 = AVPlayer(url: video1.localURL)
        self.player2 = AVPlayer(url: video2.localURL)

        setupTimeObserver()
        setupNotifications()
    }

    deinit {
        if let observer = timeObserver {
            player1.removeTimeObserver(observer)
        }
    }

    // MARK: - Time Observer (with drift correction)

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.01, preferredTimescale: 600)
        timeObserver = player1.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let t1 = CMTimeGetSeconds(time)
            self.currentTime = t1
            self.correctDriftIfNeeded(player1Time: t1)
        }
    }

    private func correctDriftIfNeeded(player1Time t1: TimeInterval) {
        guard isPlaying else { return }
        let expectedTime2 = max(0, t1 - syncOffset)
        let actualTime2 = CMTimeGetSeconds(player2.currentTime())
        let drift = abs(actualTime2 - expectedTime2)

        guard drift > maxDrift else { return }
        let cmTarget = CMTime(seconds: expectedTime2, preferredTimescale: 600)
        player2.seek(to: cmTarget, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: player1.currentItem)
            .merge(with: NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: player2.currentItem))
            .sink { [weak self] _ in
                self?.pause()
                self?.seek(to: 0)
            }
            .store(in: &cancellables)
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        // Sync player2 to correct position before starting playback
        let expectedTime2 = max(0, currentTime - syncOffset)
        let cmTarget = CMTime(seconds: expectedTime2, preferredTimescale: 600)
        player2.seek(to: cmTarget, toleranceBefore: .zero, toleranceAfter: .zero)

        player1.rate = playbackRate
        let video2Rate = tempoSyncEnabled
            ? playbackRate * video2TempoAdjustment
            : playbackRate
        player2.rate = video2Rate
        isPlaying = true
    }

    func pause() {
        player1.pause()
        player2.pause()
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        let cmTime1 = CMTime(seconds: time, preferredTimescale: 600)
        player1.seek(to: cmTime1, toleranceBefore: .zero, toleranceAfter: .zero)

        let time2 = max(0, time - syncOffset)
        let cmTime2 = CMTime(seconds: time2, preferredTimescale: 600)
        player2.seek(to: cmTime2, toleranceBefore: .zero, toleranceAfter: .zero)

        currentTime = time
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        guard isPlaying else { return }
        player1.rate = rate
        let video2Rate = tempoSyncEnabled ? rate * video2TempoAdjustment : rate
        player2.rate = video2Rate
    }

    /// Apply sync result from VideoSyncEngine
    func applySyncResult(_ result: SyncResult) {
        syncOffset = result.offset
        video2TempoAdjustment = result.video2PlaybackSpeed
        tempoSyncEnabled = false
        seek(to: currentTime)
    }

    /// Toggle tempo sync on/off
    func toggleTempoSync() {
        tempoSyncEnabled.toggle()
        guard isPlaying else { return }
        setPlaybackRate(playbackRate)
    }

    func stepFrame(forward: Bool) {
        let frameDuration = 1.0 / min(video1.fps, video2.fps)
        let newTime = forward
            ? min(currentTime + frameDuration, totalDuration)
            : max(currentTime - frameDuration, 0)
        seek(to: newTime)
    }

    func swapVideos() {
        isSwapped.toggle()
    }

    func adjustSyncOffset(by delta: TimeInterval) {
        syncOffset += delta
        seek(to: currentTime)
    }

    func setSyncOffset(_ offset: TimeInterval) {
        syncOffset = offset
        seek(to: currentTime)
    }

    // MARK: - Seek to Impact

    /// Seek both players to the impact alignment point.
    /// Contact times are absolute timestamps within each video.
    func seekToImpact(contactTime1: TimeInterval?, contactTime2: TimeInterval?) {
        guard let c1 = contactTime1 else { return }
        seek(to: c1)
    }

    // MARK: - Progress

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return currentTime / totalDuration
    }

    func seekToProgress(_ progress: Double) {
        let time = progress * totalDuration
        seek(to: time)
    }
}
