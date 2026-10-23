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

    /// Changed by the user through `select(_:)`, which is what reports the switch; the
    /// arrangement a comparison opens in is set once, silently, by `init`.
    private(set) var comparisonMode: ComparisonMode
    /// The overlay pane's opacity in stacked mode — the stage reads it directly.
    var stackedOpacity: CGFloat = 0.5
    private(set) var isSwapped = false

    /// Non-nil when the comparison composition could not be built; drives the
    /// error overlay in ComparisonView. Cleared on the next successful build.
    private(set) var buildError: String?

    nonisolated(unsafe) private var timeObserver: Any?
    private let builder = ComparisonCompositionBuilder()
    private(set) var composition: ComparisonComposition?
    private var rebuildTask: Task<Void, Never>?
    /// Monotonic token guarding the async build window: each scheduled rebuild
    /// bumps it, and a finished build only applies if its captured token is
    /// still current — stale results are dropped instead of installed.
    private var buildGeneration = 0
    private var isLooping = false
    /// True while an export renders: the item is detached so its hardware decoders are
    /// free. A build finishing meanwhile is stored, not attached.
    private var isReleased = false

    static let playbackRates: [Float] = [0.125, 0.25, 0.5, 1.0]

    var totalDuration: TimeInterval { composition?.totalDuration ?? 0 }
    var displayTime: TimeInterval { currentTime }
    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return max(0, min(1, currentTime / totalDuration))
    }

    /// Where each swing sits in the composition's frames; nil until the first build lands.
    var atlas: ComparisonAtlas? { composition?.atlas }

    /// Where the two impacts coincide on the timeline, from 0 to 1. Nil in sequential mode.
    var impactProgress: Double? {
        guard let contact = composition?.contactTime, totalDuration > 0 else { return nil }
        return contact / totalDuration
    }

    /// In sequential mode, the composition track on screen: 0 until the split, then 1.
    var sequentialSegment: Int {
        guard let split = composition?.sequentialSplit, currentTime >= split else { return 0 }
        return 1
    }

    /// The video that segment shows — the swapped order plays the second video first.
    var sequentialVideo: Int {
        isSwapped ? 1 - sequentialSegment : sequentialSegment
    }

    // MARK: - Init

    init(
        video1: SwingVideo, video2: SwingVideo,
        swing1: SwingTimeRange, swing2: SwingTimeRange,
        initialMode: ComparisonMode = .sideBySide
    ) {
        self.video1 = video1
        self.video2 = video2
        self.swing1 = swing1
        self.swing2 = swing2
        self.comparisonMode = initialMode
        self.player = AVPlayer()
        self.player.automaticallyWaitsToMinimizeStalling = false
        scheduleRebuild(seekToStart: true)
        setupTimeObserver()
    }

    deinit {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
    }

    // MARK: - Composition Lifecycle

    /// Serializes rebuilds: a newer request cancels the in-flight one so the
    /// player only ever receives the composition for the latest state.
    private func scheduleRebuild(seekToStart: Bool) {
        buildGeneration += 1
        let generation = buildGeneration
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            await self?.rebuildComposition(generation: generation, seekToStart: seekToStart)
        }
    }

    private var failureLog: ComparisonBuildFailureLog {
        ComparisonBuildFailureLog(video1: video1, video2: video2, swing1: swing1, swing2: swing2)
    }

    /// Retry entry point for the error overlay's "Try Again" button.
    func retryBuild() {
        scheduleRebuild(seekToStart: true)
    }

    private func rebuildComposition(generation: Int, seekToStart: Bool) async {
        let preservedTime = seekToStart ? 0 : currentTime
        let outcome = await builder.build(
            video1: video1, video2: video2, swing1: swing1, swing2: swing2,
            mode: comparisonMode, isSwapped: isSwapped
        )
        guard generation == buildGeneration, !Task.isCancelled else { return }
        switch outcome {
        case .success(let built):
            buildError = nil
            install(built, preservedTime: preservedTime)
        case .failure(let failure):
            failureLog.record(failure, mode: comparisonMode)
            buildError = ComparisonBuildFailureLog.userMessage
        }
    }

    /// Installs a freshly built composition. Mode, swap and opacity need no reconciling —
    /// the atlas does not depend on them — and playback resume is gated on the current
    /// `isPlaying`, so a pause tapped mid-build sticks.
    private func install(_ comp: ComparisonComposition, preservedTime: TimeInterval) {
        composition = comp
        currentTime = preservedTime
        guard !isReleased else { return }
        player.replaceCurrentItem(with: comp.playerItem)
        seekPlayer(to: preservedTime)
        if isPlaying {
            player.rate = playbackRate
        }
    }

    /// The user's own mode switch: reported, and rebuilt only when the timeline changes
    /// (sequential involved). Between the parallel modes the stage just re-arranges.
    func select(_ mode: ComparisonMode) {
        guard mode != comparisonMode else { return }
        let old = comparisonMode
        comparisonMode = mode
        Analytics.shared.track(.comparisonModeChanged(from: old, to: mode))
        guard old.playsSequentially != mode.playsSequentially else { return }
        scheduleRebuild(seekToStart: true)
    }

    // MARK: - Export Hand-off

    /// Frees the hardware decoders while an export session decodes both clips again: a
    /// paused item still holds them. (The editor before it previews on this player.)
    func releaseForExport() {
        pause()
        isReleased = true
        player.replaceCurrentItem(with: nil)
    }

    /// Re-attaches the composition where it stopped once the export sheet is gone.
    func reclaimAfterExport() {
        guard isReleased else { return }
        isReleased = false
        guard let comp = composition else { return }
        player.replaceCurrentItem(with: comp.playerItem)
        seekPlayer(to: currentTime)
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.onTick(CMTimeGetSeconds(time))
        }
    }

    private func onTick(_ time: TimeInterval) {
        // A detached item reports zero; the position to come back to is the last real one.
        guard !isReleased else { return }
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

    /// Swap is purely visual — the stage flips the pane order. Track insertion offsets
    /// (and thus impact alignment) and the audio mix are unchanged.
    func swapVideos() {
        guard comparisonMode != .sequential else { return }
        isSwapped.toggle()
    }

    // MARK: - Private Helpers

    private func seekPlayer(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
