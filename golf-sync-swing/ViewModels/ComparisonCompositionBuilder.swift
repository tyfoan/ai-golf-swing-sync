//
//  ComparisonCompositionBuilder.swift
//  golf-sync-swing
//
//  Builds an AVPlayerItem for dual-video comparison playback by baking the
//  impact-frame alignment into AVMutableComposition track insertion offsets.
//
//  This replaces the previous dual-AVPlayer + ManualPlaybackSynchronizer
//  approach. With one composition on one player there is no follower, no
//  drift correction, and no codec/fps/duration asymmetry to manage — the two
//  swings are points on a single timeline.
//
//  Layouts (sideBySide, topBottom, stacked) compose at impact-aligned offsets.
//  Sequential plays one then the other on a serial timeline.
//

import AVFoundation
import UIKit

struct ComparisonComposition {
    let playerItem: AVPlayerItem
    let totalDuration: TimeInterval
    /// Composition time where both impacts coincide. Nil for sequential mode.
    let contactTime: TimeInterval?
    let frameDuration: TimeInterval
    /// Concrete track references kept around so opacity/swap updates don't
    /// have to re-fetch by casting `AVAssetTrack` (whose runtime type isn't
    /// guaranteed to bridge cleanly on all iOS versions).
    let videoTracks: [AVCompositionTrack]
}

/// Impact-aligned timing for the synced modes (sideBySide, topBottom, stacked).
/// Each track's pre/post gap is the difference between its lead-in /
/// follow-through and the longer clip's — those gaps are filled with held
/// freeze frames by FreezeFrameInserter so the shorter clip's slot is never
/// black during the longer clip's playback.
struct SyncedTiming {
    let preGap1: TimeInterval
    let preGap2: TimeInterval
    let postGap1: TimeInterval
    let postGap2: TimeInterval
    let impactTime: TimeInterval
    let totalDuration: TimeInterval

    init(swing1: SwingTimeRange, swing2: SwingTimeRange) {
        // Clamp to non-negative: a malformed SwingTimeRange where contactTime
        // sits outside [startTime, endTime] would otherwise produce negative
        // gaps and a negative composition insertion offset.
        let leadIn1 = max(0, swing1.contactTime - swing1.startTime)
        let leadIn2 = max(0, swing2.contactTime - swing2.startTime)
        let followThrough1 = max(0, swing1.endTime - swing1.contactTime)
        let followThrough2 = max(0, swing2.endTime - swing2.contactTime)
        self.impactTime = max(leadIn1, leadIn2)
        self.totalDuration = impactTime + max(followThrough1, followThrough2)
        self.preGap1 = impactTime - leadIn1
        self.preGap2 = impactTime - leadIn2
        self.postGap1 = totalDuration - impactTime - followThrough1
        self.postGap2 = totalDuration - impactTime - followThrough2
    }
}

final class ComparisonCompositionBuilder {

    private let targetFrameRate: Int32 = 30

    func build(
        video1: SwingVideo, video2: SwingVideo,
        swing1: SwingTimeRange, swing2: SwingTimeRange,
        mode: ComparisonMode, isSwapped: Bool, stackedOpacity: CGFloat
    ) -> ComparisonComposition? {
        guard let asset1 = loadAsset(video1), let asset2 = loadAsset(video2) else { return nil }
        if mode == .sequential {
            return buildSequential(asset1, asset2, swing1: swing1, swing2: swing2, isSwapped: isSwapped)
        }
        return buildSynced(asset1, asset2, swing1: swing1, swing2: swing2,
                           mode: mode, isSwapped: isSwapped, stackedOpacity: stackedOpacity)
    }

    /// Cheap update path for changes that don't restructure tracks (mode
    /// transitions WITHIN synced modes, swap, stacked opacity). Returns nil
    /// for sequential mode — its `requiresStructuralRebuild` strategy says so.
    func makeVideoComposition(
        forTracks tracks: [AVCompositionTrack],
        totalDuration: TimeInterval,
        mode: ComparisonMode, isSwapped: Bool, stackedOpacity: CGFloat
    ) -> AVMutableVideoComposition? {
        let strategy = mode.layoutStrategy
        guard !strategy.requiresStructuralRebuild, tracks.count >= 2 else { return nil }
        let layouts = syncedLayouts(tracks: tracks, strategy: strategy, isSwapped: isSwapped, stackedOpacity: stackedOpacity)
        return makeVideoComposition(canvas: strategy.canvasSize(for: tracks), totalDuration: totalDuration, layouts: layouts)
    }

    // MARK: - Synced (impact-aligned)

    private func buildSynced(
        _ asset1: AVAsset, _ asset2: AVAsset,
        swing1: SwingTimeRange, swing2: SwingTimeRange,
        mode: ComparisonMode, isSwapped: Bool, stackedOpacity: CGFloat
    ) -> ComparisonComposition? {
        let timing = SyncedTiming(swing1: swing1, swing2: swing2)
        guard timing.totalDuration > 0 else { return nil }
        let composition = AVMutableComposition()
        guard let tracks = insertSyncedTracks(asset1, asset2, swing1: swing1, swing2: swing2, timing: timing, into: composition) else {
            return nil
        }
        let strategy = mode.layoutStrategy
        let layouts = syncedLayouts(tracks: tracks, strategy: strategy, isSwapped: isSwapped, stackedOpacity: stackedOpacity)
        let videoComposition = makeVideoComposition(canvas: strategy.canvasSize(for: tracks), totalDuration: timing.totalDuration, layouts: layouts)
        return assembleComposition(composition: composition, videoComposition: videoComposition,
                                   totalDuration: timing.totalDuration, contactTime: timing.impactTime, tracks: tracks)
    }

    private func insertSyncedTracks(
        _ asset1: AVAsset, _ asset2: AVAsset,
        swing1: SwingTimeRange, swing2: SwingTimeRange,
        timing: SyncedTiming, into composition: AVMutableComposition
    ) -> [AVCompositionTrack]? {
        guard let videoTrack1 = insertSyncedVideoTrack(asset1, swing: swing1, preGap: timing.preGap1, postGap: timing.postGap1, into: composition),
              let videoTrack2 = insertSyncedVideoTrack(asset2, swing: swing2, preGap: timing.preGap2, postGap: timing.postGap2, into: composition) else {
            return nil
        }
        insertAudio(asset1, range: swing1, into: composition, atCompositionTime: timing.preGap1)
        insertAudio(asset2, range: swing2, into: composition, atCompositionTime: timing.preGap2)
        return [videoTrack1, videoTrack2]
    }

    private func syncedLayouts(
        tracks: [AVCompositionTrack], strategy: ComparisonLayoutStrategy,
        isSwapped: Bool, stackedOpacity: CGFloat
    ) -> [TrackLayout] {
        let canvas = strategy.canvasSize(for: tracks)
        let slots = strategy.slots(in: canvas, isSwapped: isSwapped)
        return tracks.enumerated().map { index, track in
            TrackLayout(
                track: track, slot: slots[index],
                opacity: strategy.opacity(forIndex: index, stackedOpacity: stackedOpacity),
                enabledRange: nil
            )
        }
    }

    // MARK: - Sequential

    private func buildSequential(
        _ asset1: AVAsset, _ asset2: AVAsset,
        swing1: SwingTimeRange, swing2: SwingTimeRange, isSwapped: Bool
    ) -> ComparisonComposition? {
        let composition = AVMutableComposition()
        let (firstAsset, firstRange) = isSwapped ? (asset2, swing2) : (asset1, swing1)
        let (secondAsset, secondRange) = isSwapped ? (asset1, swing1) : (asset2, swing2)
        guard let tracks = insertSequentialTracks(
            firstAsset, firstRange: firstRange, secondAsset, secondRange: secondRange, into: composition
        ) else { return nil }
        let totalDuration = firstRange.duration + secondRange.duration
        let strategy = SequentialLayout()
        let canvas = strategy.canvasSize(for: tracks)
        let layouts = sequentialLayouts(tracks: tracks, canvas: canvas, firstDuration: firstRange.duration, secondDuration: secondRange.duration)
        let videoComposition = makeVideoComposition(canvas: canvas, totalDuration: totalDuration, layouts: layouts)
        return assembleComposition(composition: composition, videoComposition: videoComposition,
                                   totalDuration: totalDuration, contactTime: nil, tracks: tracks)
    }

    private func insertSequentialTracks(
        _ firstAsset: AVAsset, firstRange: SwingTimeRange,
        _ secondAsset: AVAsset, secondRange: SwingTimeRange,
        into composition: AVMutableComposition
    ) -> [AVCompositionTrack]? {
        guard let videoTrack1 = insertVideo(firstAsset, range: firstRange, into: composition, atCompositionTime: 0),
              let videoTrack2 = insertVideo(secondAsset, range: secondRange, into: composition, atCompositionTime: firstRange.duration) else {
            return nil
        }
        insertAudio(firstAsset, range: firstRange, into: composition, atCompositionTime: 0)
        insertAudio(secondAsset, range: secondRange, into: composition, atCompositionTime: firstRange.duration)
        return [videoTrack1, videoTrack2]
    }

    private func sequentialLayouts(
        tracks: [AVCompositionTrack], canvas: CGSize,
        firstDuration: TimeInterval, secondDuration: TimeInterval
    ) -> [TrackLayout] {
        let fullSlot = CGRect(origin: .zero, size: canvas)
        let firstDur = CMTime(seconds: firstDuration, preferredTimescale: 600)
        let secondDur = CMTime(seconds: secondDuration, preferredTimescale: 600)
        return [
            TrackLayout(track: tracks[0], slot: fullSlot, opacity: 1.0,
                        enabledRange: CMTimeRange(start: .zero, duration: firstDur)),
            TrackLayout(track: tracks[1], slot: fullSlot, opacity: 1.0,
                        enabledRange: CMTimeRange(start: firstDur, duration: secondDur))
        ]
    }

    // MARK: - Final Assembly

    private func assembleComposition(
        composition: AVMutableComposition, videoComposition: AVMutableVideoComposition,
        totalDuration: TimeInterval, contactTime: TimeInterval?, tracks: [AVCompositionTrack]
    ) -> ComparisonComposition {
        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = videoComposition
        playerItem.audioMix = makeAudioMix(composition: composition)
        playerItem.preferredForwardBufferDuration = 2.0
        return ComparisonComposition(
            playerItem: playerItem, totalDuration: totalDuration,
            contactTime: contactTime, frameDuration: 1.0 / Double(targetFrameRate),
            videoTracks: tracks
        )
    }

    // MARK: - Track Insertion

    private func loadAsset(_ video: SwingVideo) -> AVURLAsset? {
        guard let url = video.validLocalURL else { return nil }
        return AVURLAsset(url: url)
    }

    private func insertVideo(
        _ asset: AVAsset, range: SwingTimeRange,
        into composition: AVMutableComposition, atCompositionTime time: TimeInterval
    ) -> AVCompositionTrack? {
        guard let sourceTrack = asset.tracks(withMediaType: .video).first,
              let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }
        let sourceRange = cmTimeRange(from: range)
        try? track.insertTimeRange(sourceRange, of: sourceTrack, at: CMTime(seconds: time, preferredTimescale: 600))
        track.preferredTransform = sourceTrack.preferredTransform
        return track
    }

    /// Adapter from playback's (SwingTimeRange, TimeInterval) inputs to the
    /// shared FreezeFrameInserter's (CMTimeRange, CMTime) interface.
    private func insertSyncedVideoTrack(
        _ asset: AVAsset, swing: SwingTimeRange,
        preGap: TimeInterval, postGap: TimeInterval,
        into composition: AVMutableComposition
    ) -> AVCompositionTrack? {
        guard let sourceTrack = asset.tracks(withMediaType: .video).first else { return nil }
        return try? FreezeFrameInserter.insertVideo(
            sourceTrack: sourceTrack, sourceRange: cmTimeRange(from: swing),
            preGap: CMTime(seconds: preGap, preferredTimescale: 600),
            postGap: CMTime(seconds: postGap, preferredTimescale: 600),
            targetFrameRate: targetFrameRate, into: composition
        )
    }

    private func insertAudio(
        _ asset: AVAsset, range: SwingTimeRange,
        into composition: AVMutableComposition, atCompositionTime time: TimeInterval
    ) {
        guard let sourceTrack = asset.tracks(withMediaType: .audio).first,
              let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return
        }
        try? track.insertTimeRange(cmTimeRange(from: range), of: sourceTrack, at: CMTime(seconds: time, preferredTimescale: 600))
    }

    private func cmTimeRange(from range: SwingTimeRange) -> CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: range.startTime, preferredTimescale: 600),
            duration: CMTime(seconds: range.duration, preferredTimescale: 600)
        )
    }

    // MARK: - Video Composition

    private struct TrackLayout {
        let track: AVCompositionTrack
        let slot: CGRect
        let opacity: CGFloat
        /// Time range during which this track's layer is enabled. Nil = entire composition.
        let enabledRange: CMTimeRange?
    }

    private func makeVideoComposition(canvas: CGSize, totalDuration: TimeInterval, layouts: [TrackLayout]) -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.renderSize = canvas
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: totalDuration, preferredTimescale: 600))
        // layerInstructions are rendered top-down (index 0 on top). We pass layouts
        // in [track1, track2] order but reverse so track1 renders ABOVE track2.
        instruction.layerInstructions = layouts.map { makeLayerInstruction(for: $0) }.reversed()
        composition.instructions = [instruction]
        return composition
    }

    private func makeLayerInstruction(for layout: TrackLayout) -> AVMutableVideoCompositionLayerInstruction {
        let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: layout.track)
        instruction.setTransform(layoutTransform(for: layout.track, in: layout.slot), at: .zero)
        applyOpacity(layout: layout, to: instruction)
        return instruction
    }

    /// Sequential mode tracks have an enabledRange — hide outside, show inside.
    /// Skip the t=0 hide if the slot starts at zero, otherwise two setOpacity
    /// calls at the same time race for which wins.
    private func applyOpacity(layout: TrackLayout, to instruction: AVMutableVideoCompositionLayerInstruction) {
        guard let range = layout.enabledRange else {
            instruction.setOpacity(Float(layout.opacity), at: .zero)
            return
        }
        if range.start > .zero {
            instruction.setOpacity(0.0, at: .zero)
        }
        instruction.setOpacity(Float(layout.opacity), at: range.start)
        instruction.setOpacity(0.0, at: range.end)
    }

    private func layoutTransform(for track: AVCompositionTrack, in slot: CGRect) -> CGAffineTransform {
        let displayed = LayoutSizing.displayedSize(of: track)
        guard displayed.width > 0, displayed.height > 0 else { return track.preferredTransform }
        let scale = min(slot.width / displayed.width, slot.height / displayed.height)
        let tx = slot.midX - displayed.width * scale / 2
        let ty = slot.midY - displayed.height * scale / 2
        return track.preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }

    /// Default: video1's audio plays, video2 is muted. Matches the prior
    /// dual-player default (single clean impact thwack at export time too).
    private func makeAudioMix(composition: AVMutableComposition) -> AVAudioMix {
        let mix = AVMutableAudioMix()
        mix.inputParameters = composition.tracks(withMediaType: .audio).enumerated().map { index, track in
            let params = AVMutableAudioMixInputParameters(track: track)
            params.setVolume(index == 0 ? 1.0 : 0.0, at: .zero)
            return params
        }
        return mix
    }
}
