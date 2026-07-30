//
//  VideoPlayerViewModel.swift
//  golf-sync-swing
//

import Foundation
import AVFoundation
import Combine

@MainActor
@Observable
final class VideoPlayerViewModel {
    let player: AVPlayer
    let video: SwingVideo

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var playbackRate: Float = 1.0
    private(set) var isMuted = false

    var activeSwingBounds: (start: TimeInterval, end: TimeInterval)?

    nonisolated(unsafe) private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    static let playbackRates: [Float] = [0.125, 0.25, 0.5, 1.0]

    init(video: SwingVideo) {
        self.video = video
        self.player = AVPlayer(url: video.localURL)
        self.duration = video.duration

        setupTimeObserver()
        setupNotifications()
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Time Observer

    /// Publish cadence for `currentTime`. The observer still ticks at 100 Hz so the swing-loop
    /// bound stays precise, but `currentTime` is `@Observable`: writing it every tick invalidated
    /// SwiftUI 100×/second for the whole of playback. ~30 Hz is already past what the eye
    /// resolves and matches the source frame rate.
    private static let publishInterval: TimeInterval = 1.0 / 30.0
    private var lastPublishedTime: TimeInterval = -1

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.01, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = CMTimeGetSeconds(time)

            // Bounds get the exact tick value — that is what the 100 Hz cadence is for. Reading
            // the throttled `currentTime` here would compare against a stale value and overshoot
            // the loop point.
            self.enforceSwingBounds(at: seconds)

            guard abs(seconds - self.lastPublishedTime) >= Self.publishInterval else { return }
            self.lastPublishedTime = seconds
            self.currentTime = seconds
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .compactMap { $0.object as? AVPlayerItem }
            .filter { [weak self] item in item === self?.player.currentItem }
            .sink { [weak self] _ in
                self?.isPlaying = false
                self?.seek(to: 0)
            }
            .store(in: &cancellables)
    }

    private func enforceSwingBounds(at time: TimeInterval) {
        guard let bounds = activeSwingBounds, isPlaying else { return }
        guard time >= bounds.end else { return }
        seek(to: bounds.start)
        play()
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        player.rate = playbackRate
        isPlaying = true
    }

    func pause() {
        player.pause()
        // Re-sync exactly on pause. The observer stops firing once time stops advancing, so
        // without this `currentTime` could sit up to one publish interval stale — and
        // frame-stepping computes from it, which would land on the wrong frame.
        let exact = CMTimeGetSeconds(player.currentTime())
        if exact.isFinite {
            currentTime = exact
            lastPublishedTime = exact
        }
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        // Keep the invariant: lastPublishedTime always mirrors the last value written to
        // currentTime, so the observer's throttle measures from where we actually are.
        lastPublishedTime = time
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player.rate = rate }
    }

    func stepFrame(forward: Bool) {
        let frameDuration = 1.0 / video.fps
        let newTime = forward
            ? min(currentTime + frameDuration, duration)
            : max(currentTime - frameDuration, 0)
        seek(to: newTime)
    }

    // MARK: - Mute

    func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
    }

    // MARK: - Swing Playback

    /// Whether a swing marker has valid timestamps for this video.
    /// Markers recorded before the timestamp normalization fix have
    /// host-clock values (e.g. 86400) instead of file-relative values.
    func isSwingValid(_ swing: SwingMarker) -> Bool {
        swing.startTime <= duration && swing.endTime <= duration + 1.0
    }

    func playSwing(_ swing: SwingMarker) {
        guard isSwingValid(swing) else { return }
        activeSwingBounds = (swing.startTime, swing.endTime)
        seek(to: swing.startTime)
        play()
    }

    func clearSwingBounds() {
        activeSwingBounds = nil
    }

    // MARK: - Progress

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    func seekToProgress(_ progress: Double) {
        let time = progress * duration
        seek(to: time)
    }
}
