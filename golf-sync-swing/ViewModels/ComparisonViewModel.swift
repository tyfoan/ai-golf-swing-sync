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

    /// Non-nil when the comparison composition could not be built; drives the
    /// error overlay in ComparisonView. Cleared on the next successful build.
    private(set) var buildError: String?

    nonisolated(unsafe) private var timeObserver: Any?
    private let builder = ComparisonCompositionBuilder()
    private var composition: ComparisonComposition?
    private var rebuildTask: Task<Void, Never>?
    /// Monotonic token guarding the async build window: each scheduled rebuild
    /// bumps it, and a finished build only applies if its captured token is
    /// still current — stale results are dropped instead of installed.
    private var buildGeneration = 0
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

    /// Retry entry point for the error overlay's "Try Again" button.
    func retryBuild() {
        scheduleRebuild(seekToStart: true)
    }

    private func rebuildComposition(generation: Int, seekToStart: Bool) async {
        let preservedTime = seekToStart ? 0 : currentTime
        let outcome = await builder.build(
            video1: video1, video2: video2, swing1: swing1, swing2: swing2,
            mode: comparisonMode, isSwapped: isSwapped, stackedOpacity: stackedOpacity
        )
        guard generation == buildGeneration, !Task.isCancelled else { return }
        switch outcome {
        case .success(let built):
            buildError = nil
            install(built, preservedTime: preservedTime)
        case .failure(let failure):
            report(failure)
        }
    }

    /// The user reads the same sentence whichever way the build failed — there is nothing
    /// they can do about an AVFoundation insertion error — but the REASON has to survive
    /// somewhere. A bare nil here is what made "comparison is broken" a report with no
    /// possible follow-up: the log line and the DEBUG timeline now name the failing side
    /// and say whether the file, the movie, or the marker was at fault.
    private func report(_ failure: ComparisonBuildFailure) {
        let detail = failure.diagnosticDetail ?? "none"
        // `.public`: the point of a reason is reading it off a device log, and an
        // interpolated string is redacted to <private> by default.
        AppLogger.sync.error("ComparisonViewModel: build failed reason=\(failure.probeReason, privacy: .public) detail=\(detail, privacy: .public)")
        #if DEBUG
        DeviceProbe.event("comparison_build_failed", [
            "reason": failure.probeReason,
            "detail": detail,
            "mode": comparisonMode.rawValue,
            // The two inputs the reason has to be read against: whether each file is still
            // there, and what its marker asked for.
            "file1_exists": String(video1.fileExists),
            "file2_exists": String(video2.fileExists),
            "swing1_s": Self.rangeLabel(swing1),
            "swing2_s": Self.rangeLabel(swing2)
        ], ui: true)
        #endif
        buildError = String(localized: "Couldn't load these videos. They may have been moved or deleted.", comment: "Error shown on the comparison screen when the two swing videos fail to load for playback")
    }

    #if DEBUG
    private static func rangeLabel(_ range: SwingTimeRange) -> String {
        String(format: "%.2f/%.2f/%.2f", range.startTime, range.contactTime, range.endTime)
    }
    #endif

    /// Installs a freshly built composition, then reconciles against LIVE
    /// state: layer-only properties (mode/swap/opacity) mutated during the
    /// async build window are re-applied via `updateVideoComposition()`, and
    /// playback resume is gated on the current `isPlaying` so a pause tapped
    /// mid-build sticks.
    private func install(_ comp: ComparisonComposition, preservedTime: TimeInterval) {
        composition = comp
        player.replaceCurrentItem(with: comp.playerItem)
        updateVideoComposition()
        seekPlayer(to: preservedTime)
        currentTime = preservedTime
        if isPlaying {
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
        Analytics.shared.track(.comparisonModeChanged(from: old, to: comparisonMode))
        // If either side of the transition restructures the timeline (i.e.
        // sequential involved), full-rebuild. Otherwise it's a layer-only
        // change and a cheap videoComposition swap suffices.
        let needsRebuild = old.layoutStrategy.requiresStructuralRebuild
            || comparisonMode.layoutStrategy.requiresStructuralRebuild
        if needsRebuild {
            scheduleRebuild(seekToStart: true)
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
