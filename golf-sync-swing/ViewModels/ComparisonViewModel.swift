//
//  ComparisonViewModel.swift
//  golf-sync-swing
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

    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var isSwapped = false

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

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.01, preferredTimescale: 600)
        timeObserver = player1.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = CMTimeGetSeconds(time)
        }
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
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
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
        let cmTime1 = CMTime(seconds: time, preferredTimescale: 600)
        player1.seek(to: cmTime1, toleranceBefore: .zero, toleranceAfter: .zero)

        // Apply sync offset to second video
        let time2 = max(0, time - syncOffset)
        let cmTime2 = CMTime(seconds: time2, preferredTimescale: 600)
        player2.seek(to: cmTime2, toleranceBefore: .zero, toleranceAfter: .zero)

        currentTime = time
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player1.rate = rate
            player2.rate = rate
        }
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
        // Re-sync to current position with new offset
        seek(to: currentTime)
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return currentTime / totalDuration
    }

    func seekToProgress(_ progress: Double) {
        let time = progress * totalDuration
        seek(to: time)
    }
}
