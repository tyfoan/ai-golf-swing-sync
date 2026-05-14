//
//  ComparisonViewModel.swift
//  golf-sync-swing
//
//  Orchestrates dual-video comparison playback through a SINGLE AVPlayer
//  driving an AVMutableComposition. Impact alignment is baked into track
//  insertion offsets by `ComparisonCompositionBuilder`, eliminating runtime
//  drift correction and the codec/fps/duration asymmetry that the
//  previous dual-player + ManualPlaybackSynchronizer architecture suffered
//  from (heavier-decoder-as-follower stutter).
//
//  Layouts (sideBySide, topBottom, stacked, sequential) are expressed as
//  composition-level transforms + opacities; the SwiftUI side renders a
//  single AVPlayerLayer of the composited output.
//

import Foundation
import AVFoundation
import os

@MainActor
@Observable
final class ComparisonViewModel {
    let player: AVPlayer
    let video1: SwingVideo
    let video2: SwingVideo
    let swing1: SwingTimeRange
    let swing2: SwingTimeRange

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var playbackRate: Float = 1.0

    /// Impact-time delta between the two source clips. Consumed by the export
    /// pipeline (not by playback — playback's sync is baked into the
    /// composition's track offsets).
    var syncOffset: TimeInterval { swing1.contactTime - swing2.contactTime }

    var comparisonMode: ComparisonMode = .sideBySide {
        didSet {
            guard oldValue != comparisonMode else { return }
            onModeChanged(from: oldValue)
        }
    }
    var stackedOpacity: CGFloat = 0.5 {
        didSet {
            guard oldValue != stackedOpacity, comparisonMode == .stacked else { return }
            updateVideoComposition()
        }
    }
    private(set) var isSwapped = false

    nonisolated(unsafe) private var timeObserver: Any?
    private let builder = ComparisonCompositionBuilder()
    private var composition: ComparisonComposition?
    private var isLooping = false

    static let playbackRates: [Float] = [0.125, 0.25, 0.5, 1.0]

    var totalDuration: TimeInterval { composition?.totalDuration ?? 0 }
    var displayTime: TimeInterval { currentTime }
    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return max(0, min(1, currentTime / totalDuration))
    }

    // MARK: - Init

    init(video1: SwingVideo, video2: SwingVideo, swing1: SwingTimeRange, swing2: SwingTimeRange) {
        self.video1 = video1
        self.video2 = video2
        self.swing1 = swing1
        self.swing2 = swing2
        self.player = AVPlayer()
        self.player.automaticallyWaitsToMinimizeStalling = false
        rebuildComposition(seekToStart: true)
        setupTimeObserver()
    }

    deinit {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
    }

    func cleanup() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let obs = timeObserver { player.removeTimeObserver(obs); timeObserver = nil }
        isPlaying = false
    }

    // MARK: - Composition Lifecycle

    private func rebuildComposition(seekToStart: Bool) {
        let preservedTime = seekToStart ? 0 : currentTime
        let wasPlaying = isPlaying
        guard let comp = builder.build(
            video1: video1, video2: video2, swing1: swing1, swing2: swing2,
            mode: comparisonMode, isSwapped: isSwapped, stackedOpacity: stackedOpacity
        ) else {
            AppLogger.detection.error("ComparisonViewModel: failed to build composition")
            return
        }
        composition = comp
        player.replaceCurrentItem(with: comp.playerItem)
        seekPlayer(to: preservedTime)
        currentTime = preservedTime
        if wasPlaying {
            player.rate = playbackRate
        }
    }

    private func updateVideoComposition() {
        guard let comp = composition,
              let videoComposition = builder.makeVideoComposition(
                  forTracks: comp.videoTracks, totalDuration: comp.totalDuration,
                  mode: comparisonMode, isSwapped: isSwapped, stackedOpacity: stackedOpacity
              ) else { return }
        comp.playerItem.videoComposition = videoComposition
    }

    private func onModeChanged(from old: ComparisonMode) {
        // Sequential ↔ synced changes the track time offsets; must full-rebuild.
        // Synced ↔ synced only changes layer instructions; cheap update.
        let needsStructuralRebuild = (old == .sequential) != (comparisonMode == .sequential)
        if needsStructuralRebuild {
            rebuildComposition(seekToStart: true)
        } else {
            updateVideoComposition()
        }
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.onTick(CMTimeGetSeconds(time))
        }
    }

    private func onTick(_ time: TimeInterval) {
        currentTime = time
        guard isPlaying, !isLooping, totalDuration > 0, time >= totalDuration - 0.01 else { return }
        loopToStart()
    }

    private func loopToStart() {
        isLooping = true
        let cmTime = CMTime.zero
        let tolerance = CMTime(seconds: 0.04, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLooping = false
                if self.isPlaying { self.player.rate = self.playbackRate }
            }
        }
        currentTime = 0
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        if currentTime >= totalDuration - 0.01 {
            seekPlayer(to: 0)
            currentTime = 0
        }
        player.rate = playbackRate
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
        isLooping = false
    }

    func seek(to time: TimeInterval) {
        guard time.isFinite, totalDuration > 0 else { return }
        let clamped = max(0, min(totalDuration, time))
        seekPlayer(to: clamped)
        currentTime = clamped
    }

    func seekToProgress(_ progress: Double) {
        seek(to: progress * totalDuration)
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player.rate = rate
        }
    }

    func stepFrame(forward: Bool) {
        let step = composition?.frameDuration ?? (1.0 / 30.0)
        seek(to: forward ? currentTime + step : currentTime - step)
    }

    /// Swap is purely visual — flips which slot each track renders in. Track
    /// insertion offsets (and thus impact alignment) are unchanged.
    func swapVideos() {
        guard comparisonMode != .sequential else { return }
        isSwapped.toggle()
        updateVideoComposition()
    }

    // MARK: - Private Helpers

    private func seekPlayer(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
