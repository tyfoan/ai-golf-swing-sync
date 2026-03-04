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
    }

    func cleanup() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        cancellables.removeAll()
    }

    // MARK: - Time Observer

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.01, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = CMTimeGetSeconds(time)
            self.enforceSwingBounds()
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
            .sink { [weak self] _ in
                self?.isPlaying = false
                self?.seek(to: 0)
            }
            .store(in: &cancellables)
    }

    private func enforceSwingBounds() {
        guard let bounds = activeSwingBounds, isPlaying else { return }
        guard currentTime >= bounds.end else { return }
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
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
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

    func playSwing(_ swing: SwingMarker) {
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
