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

final class ComparisonCompositionBuilder {

    private let targetFrameRate: Int32 = 30
    private let maxRenderEdge: CGFloat = 1920

    func build(
        video1: SwingVideo, video2: SwingVideo,
        swing1: SwingTimeRange, swing2: SwingTimeRange,
        mode: ComparisonMode, isSwapped: Bool, stackedOpacity: CGFloat
    ) -> ComparisonComposition? {
        guard let asset1 = loadAsset(video1), let asset2 = loadAsset(video2) else { return nil }
        switch mode {
        case .sequential:
            return buildSequential(asset1, asset2, swing1: swing1, swing2: swing2, isSwapped: isSwapped)
        case .sideBySide, .topBottom, .stacked:
            return buildSynced(
                asset1, asset2, swing1: swing1, swing2: swing2,
                mode: mode, isSwapped: isSwapped, stackedOpacity: stackedOpacity
            )
        }
    }

    /// Cheap update path for changes that don't restructure tracks (mode
    /// transitions WITHIN synced modes, swap, stacked opacity). Returns nil
    /// for sequential mode — that requires a full structural rebuild.
    func makeVideoComposition(
        forTracks tracks: [AVCompositionTrack],
        totalDuration: TimeInterval,
        mode: ComparisonMode, isSwapped: Bool, stackedOpacity: CGFloat
    ) -> AVMutableVideoComposition? {
        guard mode != .sequential, tracks.count >= 2 else { return nil }
        let track1 = tracks[0]
        let track2 = tracks[1]
        let canvas = renderSize(for: mode, tracks: [track1, track2])
        let slots = slots(for: mode, in: canvas, isSwapped: isSwapped)
        let layouts: [TrackLayout] = [
            TrackLayout(track: track1, slot: slots[0], opacity: opacity(for: mode, index: 0, stackedOpacity: stackedOpacity), enabledRange: nil),
            TrackLayout(track: track2, slot: slots[1], opacity: opacity(for: mode, index: 1, stackedOpacity: stackedOpacity), enabledRange: nil)
        ]
        return makeVideoComposition(canvas: canvas, totalDuration: totalDuration, layouts: layouts)
    }

    // MARK: - Synced (impact-aligned)

    private func buildSynced(
        _ asset1: AVAsset, _ asset2: AVAsset,
        swing1: SwingTimeRange, swing2: SwingTimeRange,
        mode: ComparisonMode, isSwapped: Bool, stackedOpacity: CGFloat
    ) -> ComparisonComposition? {
        // Clamp to non-negative: a malformed SwingTimeRange where contactTime
        // sits outside [startTime, endTime] would otherwise produce negative
        // gaps and a negative composition insertion offset.
        let leadIn1 = max(0, swing1.contactTime - swing1.startTime)
        let leadIn2 = max(0, swing2.contactTime - swing2.startTime)
        let followThrough1 = max(0, swing1.endTime - swing1.contactTime)
        let followThrough2 = max(0, swing2.endTime - swing2.contactTime)
        let impactTime = max(leadIn1, leadIn2)
        let totalDuration = impactTime + max(followThrough1, followThrough2)
        guard totalDuration > 0 else { return nil }

        let composition = AVMutableComposition()
        let preGap1 = impactTime - leadIn1
        let preGap2 = impactTime - leadIn2
        let postGap1 = totalDuration - impactTime - followThrough1
        let postGap2 = totalDuration - impactTime - followThrough2
        guard let videoTrack1 = insertVideoWithFreezeFrames(asset1, range: swing1, into: composition, preGap: preGap1, postGap: postGap1),
              let videoTrack2 = insertVideoWithFreezeFrames(asset2, range: swing2, into: composition, preGap: preGap2, postGap: postGap2) else {
            return nil
        }
        insertAudio(asset1, range: swing1, into: composition, atCompositionTime: preGap1)
        insertAudio(asset2, range: swing2, into: composition, atCompositionTime: preGap2)

        let canvas = renderSize(for: mode, tracks: [videoTrack1, videoTrack2])
        let slots = slots(for: mode, in: canvas, isSwapped: isSwapped)
        let layouts: [TrackLayout] = [
            TrackLayout(track: videoTrack1, slot: slots[0], opacity: opacity(for: mode, index: 0, stackedOpacity: stackedOpacity), enabledRange: nil),
            TrackLayout(track: videoTrack2, slot: slots[1], opacity: opacity(for: mode, index: 1, stackedOpacity: stackedOpacity), enabledRange: nil)
        ]

        let videoComposition = makeVideoComposition(canvas: canvas, totalDuration: totalDuration, layouts: layouts)
        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = videoComposition
        playerItem.audioMix = makeAudioMix(composition: composition)
        playerItem.preferredForwardBufferDuration = 2.0

        return ComparisonComposition(
            playerItem: playerItem,
            totalDuration: totalDuration,
            contactTime: impactTime,
            frameDuration: 1.0 / Double(targetFrameRate),
            videoTracks: [videoTrack1, videoTrack2]
        )
    }

    // MARK: - Sequential

    private func buildSequential(
        _ asset1: AVAsset, _ asset2: AVAsset,
        swing1: SwingTimeRange, swing2: SwingTimeRange, isSwapped: Bool
    ) -> ComparisonComposition? {
        let composition = AVMutableComposition()
        let firstRange = isSwapped ? swing2 : swing1
        let firstAsset = isSwapped ? asset2 : asset1
        let secondRange = isSwapped ? swing1 : swing2
        let secondAsset = isSwapped ? asset1 : asset2

        guard let videoTrack1 = insertVideo(firstAsset, range: firstRange, into: composition, atCompositionTime: 0),
              let videoTrack2 = insertVideo(secondAsset, range: secondRange, into: composition, atCompositionTime: firstRange.duration) else {
            return nil
        }
        insertAudio(firstAsset, range: firstRange, into: composition, atCompositionTime: 0)
        insertAudio(secondAsset, range: secondRange, into: composition, atCompositionTime: firstRange.duration)

        let totalDuration = firstRange.duration + secondRange.duration
        let canvas = renderSize(for: .sequential, tracks: [videoTrack1, videoTrack2])
        let fullSlot = CGRect(origin: .zero, size: canvas)
        let layouts: [TrackLayout] = [
            TrackLayout(track: videoTrack1, slot: fullSlot, opacity: 1.0,
                        enabledRange: CMTimeRange(start: .zero, duration: CMTime(seconds: firstRange.duration, preferredTimescale: 600))),
            TrackLayout(track: videoTrack2, slot: fullSlot, opacity: 1.0,
                        enabledRange: CMTimeRange(start: CMTime(seconds: firstRange.duration, preferredTimescale: 600),
                                                  duration: CMTime(seconds: secondRange.duration, preferredTimescale: 600)))
        ]

        let videoComposition = makeVideoComposition(canvas: canvas, totalDuration: totalDuration, layouts: layouts)
        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = videoComposition
        playerItem.audioMix = makeAudioMix(composition: composition)
        playerItem.preferredForwardBufferDuration = 2.0

        return ComparisonComposition(
            playerItem: playerItem,
            totalDuration: totalDuration,
            contactTime: nil,
            frameDuration: 1.0 / Double(targetFrameRate),
            videoTracks: [videoTrack1, videoTrack2]
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
        let timeRange = CMTimeRange(
            start: CMTime(seconds: range.startTime, preferredTimescale: 600),
            duration: CMTime(seconds: range.duration, preferredTimescale: 600)
        )
        try? track.insertTimeRange(timeRange, of: sourceTrack, at: CMTime(seconds: time, preferredTimescale: 600))
        track.preferredTransform = sourceTrack.preferredTransform
        return track
    }

    /// For synced modes: places the swing's main range plus held first/last
    /// frames covering any pre/post gap relative to the other track. Without
    /// this, the shorter clip's slot renders black during the longer clip's
    /// lead-in / follow-through. We freeze (don't loop or interpolate) — that
    /// matches the standard side-by-side swing-tool convention: hold the
    /// address pose at start, hold the finish pose at end.
    private func insertVideoWithFreezeFrames(
        _ asset: AVAsset, range: SwingTimeRange,
        into composition: AVMutableComposition,
        preGap: TimeInterval, postGap: TimeInterval
    ) -> AVCompositionTrack? {
        guard let sourceTrack = asset.tracks(withMediaType: .video).first,
              let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }
        let oneFrame = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
        let oneFrameSeconds = 1.0 / Double(targetFrameRate)
        let minFreezeSeconds = oneFrameSeconds * 2
        let mainStart = CMTime(seconds: range.startTime, preferredTimescale: 600)
        let mainDuration = CMTime(seconds: range.duration, preferredTimescale: 600)
        var cursor: CMTime = .zero

        if preGap >= minFreezeSeconds {
            let freezeSrc = CMTimeRange(start: mainStart, duration: oneFrame)
            try? track.insertTimeRange(freezeSrc, of: sourceTrack, at: cursor)
            let stretchTarget = CMTime(seconds: preGap, preferredTimescale: 600)
            track.scaleTimeRange(CMTimeRange(start: cursor, duration: oneFrame), toDuration: stretchTarget)
            cursor = cursor + stretchTarget
        }

        try? track.insertTimeRange(CMTimeRange(start: mainStart, duration: mainDuration), of: sourceTrack, at: cursor)
        cursor = cursor + mainDuration

        if postGap >= minFreezeSeconds, range.duration >= oneFrameSeconds {
            let lastFrameStart = mainStart + mainDuration - oneFrame
            let freezeSrc = CMTimeRange(start: lastFrameStart, duration: oneFrame)
            try? track.insertTimeRange(freezeSrc, of: sourceTrack, at: cursor)
            let stretchTarget = CMTime(seconds: postGap, preferredTimescale: 600)
            track.scaleTimeRange(CMTimeRange(start: cursor, duration: oneFrame), toDuration: stretchTarget)
        }

        track.preferredTransform = sourceTrack.preferredTransform
        return track
    }

    private func insertAudio(
        _ asset: AVAsset, range: SwingTimeRange,
        into composition: AVMutableComposition, atCompositionTime time: TimeInterval
    ) {
        guard let sourceTrack = asset.tracks(withMediaType: .audio).first,
              let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return
        }
        let timeRange = CMTimeRange(
            start: CMTime(seconds: range.startTime, preferredTimescale: 600),
            duration: CMTime(seconds: range.duration, preferredTimescale: 600)
        )
        try? track.insertTimeRange(timeRange, of: sourceTrack, at: CMTime(seconds: time, preferredTimescale: 600))
    }

    // MARK: - Layout

    private struct TrackLayout {
        let track: AVCompositionTrack
        let slot: CGRect
        let opacity: CGFloat
        /// Time range during which this track's layer is enabled. Nil = entire composition.
        let enabledRange: CMTimeRange?
    }

    private func renderSize(for mode: ComparisonMode, tracks: [AVCompositionTrack]) -> CGSize {
        let sizes = tracks.map { displayedSize(of: $0) }
        let widths = sizes.map { $0.width }
        let heights = sizes.map { $0.height }
        let raw: CGSize
        switch mode {
        case .sideBySide:  raw = CGSize(width: widths.reduce(0, +), height: heights.max() ?? 0)
        case .topBottom:   raw = CGSize(width: widths.max() ?? 0, height: heights.reduce(0, +))
        case .stacked, .sequential: raw = CGSize(width: widths.max() ?? 0, height: heights.max() ?? 0)
        }
        return cap(raw, longestEdge: maxRenderEdge)
    }

    private func slots(for mode: ComparisonMode, in canvas: CGSize, isSwapped: Bool) -> [CGRect] {
        let full = CGRect(origin: .zero, size: canvas)
        switch mode {
        case .sideBySide:
            let half = CGRect(x: 0, y: 0, width: canvas.width / 2, height: canvas.height)
            let right = CGRect(x: canvas.width / 2, y: 0, width: canvas.width / 2, height: canvas.height)
            return isSwapped ? [right, half] : [half, right]
        case .topBottom:
            let top = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height / 2)
            let bottom = CGRect(x: 0, y: canvas.height / 2, width: canvas.width, height: canvas.height / 2)
            return isSwapped ? [bottom, top] : [top, bottom]
        case .stacked, .sequential:
            return [full, full]
        }
    }

    private func opacity(for mode: ComparisonMode, index: Int, stackedOpacity: CGFloat) -> CGFloat {
        guard mode == .stacked, index == 1 else { return 1.0 }
        return stackedOpacity
    }

    private func displayedSize(of track: AVCompositionTrack) -> CGSize {
        let raw = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
        return CGSize(width: abs(raw.width), height: abs(raw.height))
    }

    private func cap(_ size: CGSize, longestEdge: CGFloat) -> CGSize {
        let longest = max(size.width, size.height)
        let scale = longest > longestEdge ? longestEdge / longest : 1.0
        return CGSize(width: even(size.width * scale), height: even(size.height * scale))
    }

    /// Force even dimensions — hardware video codecs reject odd renderSize.
    private func even(_ value: CGFloat) -> CGFloat {
        max(2, round(value / 2) * 2)
    }

    // MARK: - Video Composition

    private func makeVideoComposition(canvas: CGSize, totalDuration: TimeInterval, layouts: [TrackLayout]) -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.renderSize = canvas
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: totalDuration, preferredTimescale: 600))
        instruction.layerInstructions = layouts.map { makeLayerInstruction(for: $0, canvas: canvas) }.reversed()
        composition.instructions = [instruction]
        return composition
    }

    /// Note: layerInstructions are rendered TOP-DOWN in the array — i.e. the
    /// first instruction is the topmost layer. We pass layouts in [track1, track2]
    /// order but reverse before assigning so track1 renders ABOVE track2 in stacked
    /// mode (matching the prior dual-AVPlayerLayer rendering order).
    private func makeLayerInstruction(for layout: TrackLayout, canvas: CGSize) -> AVMutableVideoCompositionLayerInstruction {
        let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: layout.track)
        let transform = layoutTransform(for: layout.track, in: layout.slot)
        instruction.setTransform(transform, at: .zero)
        if let range = layout.enabledRange {
            // Sequential mode: hide outside the track's slot, show inside.
            // Skip the t=0 hide if the slot starts at zero, otherwise two
            // setOpacity calls at the same time race for which wins.
            if range.start > .zero {
                instruction.setOpacity(0.0, at: .zero)
            }
            instruction.setOpacity(Float(layout.opacity), at: range.start)
            instruction.setOpacity(0.0, at: range.end)
        } else {
            instruction.setOpacity(Float(layout.opacity), at: .zero)
        }
        return instruction
    }

    private func layoutTransform(for track: AVCompositionTrack, in slot: CGRect) -> CGAffineTransform {
        let displayed = displayedSize(of: track)
        guard displayed.width > 0, displayed.height > 0 else { return track.preferredTransform }
        let scale = min(slot.width / displayed.width, slot.height / displayed.height)
        let scaledSize = CGSize(width: displayed.width * scale, height: displayed.height * scale)
        let tx = slot.midX - scaledSize.width / 2
        let ty = slot.midY - scaledSize.height / 2
        return track.preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }

    // MARK: - Audio Mix

    /// Default: video1's audio plays, video2 is muted. Matches the prior
    /// dual-player default (single clean impact thwack at export time too).
    private func makeAudioMix(composition: AVMutableComposition) -> AVAudioMix {
        let mix = AVMutableAudioMix()
        let audioTracks = composition.tracks(withMediaType: .audio)
        mix.inputParameters = audioTracks.enumerated().map { index, track in
            let params = AVMutableAudioMixInputParameters(track: track)
            params.setVolume(index == 0 ? 1.0 : 0.0, at: .zero)
            return params
        }
        return mix
    }
}
