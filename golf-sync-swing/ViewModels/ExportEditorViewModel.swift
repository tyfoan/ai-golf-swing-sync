//
//  ExportEditorViewModel.swift
//  golf-sync-swing
//
//  Owns the editor's two AVPlayers, per-video transforms, and exposes
//  the methods the editor view binds to. Pure logic for transforms is
//  testable without spinning up real AVPlayers.
//

import Foundation
import AVFoundation
import Observation

@Observable
final class ExportEditorViewModel {

    let aspectRatio: ExportAspectRatio
    var transforms: [VideoTransform] {
        didSet { syncMuteToPlayers() }
    }
    var isPlaying: Bool = true

    private(set) var player1: AVPlayer?
    private(set) var player2: AVPlayer?

    private let video1URL: URL?
    private let video2URL: URL?
    private let swing1: SwingTimeRange?
    private let swing2: SwingTimeRange?
    private let syncOffset: TimeInterval

    private var loopObserver1: Any?
    private var loopObserver2: Any?

    init(
        aspectRatio: ExportAspectRatio,
        video1URL: URL,
        video2URL: URL,
        swing1: SwingTimeRange,
        swing2: SwingTimeRange,
        syncOffset: TimeInterval
    ) {
        self.aspectRatio = aspectRatio
        self.video1URL = video1URL
        self.video2URL = video2URL
        self.swing1 = swing1
        self.swing2 = swing2
        self.syncOffset = syncOffset
        self.transforms = Self.defaultTransforms()
    }

    /// Test-only init — no AVPlayers, just transforms.
    private init(aspectRatio: ExportAspectRatio) {
        self.aspectRatio = aspectRatio
        self.video1URL = nil
        self.video2URL = nil
        self.swing1 = nil
        self.swing2 = nil
        self.syncOffset = 0
        self.transforms = Self.defaultTransforms()
    }

    static func makeForTesting(aspectRatio: ExportAspectRatio) -> ExportEditorViewModel {
        ExportEditorViewModel(aspectRatio: aspectRatio)
    }

    private static func defaultTransforms() -> [VideoTransform] {
        let v1 = VideoTransform()
        var v2 = VideoTransform()
        v2.isMuted = true
        return [v1, v2]
    }

    func setupPlayers() {
        guard let url1 = video1URL, let url2 = video2URL,
              let s1 = swing1, let s2 = swing2 else { return }
        let p1 = AVPlayer(url: url1)
        let p2 = AVPlayer(url: url2)
        seek(player: p1, to: s1.startTime)
        seek(player: p2, to: Self.player2InitialPosition(s1: s1, s2: s2))
        installLoopObservers(p1: p1, p2: p2, s1: s1, s2: s2)
        self.player1 = p1
        self.player2 = p2
        syncMuteToPlayers()
        play()
    }

    /// Mirrors `transforms[i].isMuted` onto each AVPlayer's `isMuted` so the
    /// editor preview hears what the export will produce.
    private func syncMuteToPlayers() {
        if transforms.indices.contains(0) { player1?.isMuted = transforms[0].isMuted }
        if transforms.indices.contains(1) { player2?.isMuted = transforms[1].isMuted }
    }

    /// Aligns video2's playhead so the contact frame coincides with video1's
    /// contact at the same wall-clock moment — matching the export pipeline,
    /// which applies the same offset as a track insertion offset.
    /// Clamped to >= 0 to avoid pre-roll seeking; in edge cases where the gap
    /// in s2 exceeds the gap in s1 by more than s2.startTime, contact alignment
    /// is approximate (rare; user can pinch/drag to fine-tune).
    static func player2InitialPosition(s1: SwingTimeRange, s2: SwingTimeRange) -> TimeInterval {
        let raw = s2.startTime + (s2.contactTime - s2.startTime) - (s1.contactTime - s1.startTime)
        return max(0, raw)
    }

    func play() {
        player1?.play()
        player2?.play()
        isPlaying = true
    }

    func pause() {
        player1?.pause()
        player2?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func toggleMute(at index: Int) {
        guard transforms.indices.contains(index) else { return }
        transforms[index].isMuted.toggle()
    }

    func buildLayoutConfig() -> VideoLayoutConfig {
        VideoLayoutConfig(aspectRatio: aspectRatio, transforms: transforms)
    }

    func cleanup() {
        if let o = loopObserver1 { player1?.removeTimeObserver(o); loopObserver1 = nil }
        if let o = loopObserver2 { player2?.removeTimeObserver(o); loopObserver2 = nil }
        player1?.pause(); player2?.pause()
        // Drop the AVPlayerItems before releasing the players to avoid the leak/hang
        // pattern documented in production hardening (Mar 1 2026).
        player1?.replaceCurrentItem(with: nil)
        player2?.replaceCurrentItem(with: nil)
        player1 = nil; player2 = nil
    }

    private func seek(player: AVPlayer, to time: TimeInterval) {
        let cm = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func installLoopObservers(p1: AVPlayer, p2: AVPlayer, s1: SwingTimeRange, s2: SwingTimeRange) {
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        let p2InitialPosition = Self.player2InitialPosition(s1: s1, s2: s2)
        loopObserver1 = p1.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak p1] _ in
            guard let self, let player = p1 else { return }
            if player.currentTime().seconds >= s1.endTime - 0.01 {
                self.seek(player: player, to: s1.startTime)
                if let p2 = self.player2 { self.seek(player: p2, to: p2InitialPosition) }
            }
        }
    }
}
