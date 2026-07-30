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
//  TWO RULES THIS FILE EXISTS TO HOLD, both learned the hard way:
//
//  1. THE SOURCE ASSETS MUST OUTLIVE EVERY INSERT. `AVAssetTrack.asset` is a weak
//     back-reference, so a track handed around without its `AVURLAsset` is orphaned the
//     moment the loader returns — and `insertTimeRange(_:of:at:)` then fails against it
//     with AVFoundationErrorDomain -11800 (-12780) for EVERY range, valid ones included.
//     That is why `SourceTracks` carries the asset. (Afterwards the composition is
//     self-sufficient: its segments reference the source by URL, so nothing needs to
//     retain the assets once the build has returned.)
//  2. A FAILURE MUST SAY WHY. The builder used to answer `nil`, which reached the user as
//     one sentence and reached us as nothing at all. It now returns a
//     `ComparisonBuildFailure`, which the view model logs and puts on the DEBUG timeline.
//

import AVFoundation
import UIKit

/// Which of the two swings a failure belongs to. Present in every per-side reason so a
/// timeline line says WHICH video was missing, not merely that one was.
enum ComparisonSide {
    case first, second

    var probeLabel: String {
        switch self {
        case .first: return "1"
        case .second: return "2"
        }
    }
}

/// Why a comparison composition could not be built.
///
/// Replaces a bare `nil`. The builder can fail for reasons with nothing in common — a file
/// deleted out from under a record, a movie with no video track, a marker that names
/// footage the take does not contain, an AVFoundation insertion error — and collapsing all
/// of them into one absent value is what made "comparison is broken" unanswerable without
/// a device in hand. The user still reads one sentence; the reason goes to the log and the
/// DEBUG timeline.
enum ComparisonBuildFailure: Error {
    case fileMissing(ComparisonSide)
    case noVideoTrack(ComparisonSide)
    /// Nothing of the marker's range survives inside the video's own footage.
    case swingRangeOutsideVideo(ComparisonSide)
    /// Both swings have zero lead-in AND zero follow-through: no timeline to align on.
    case alignmentCollapsed
    case trackAllocationFailed
    /// AVFoundation refused an insert; the string is its own message.
    case insertionFailed(String)

    /// Anything raised below that is not already one of ours — in practice the
    /// `insertTimeRange` errors `FreezeFrameInserter` propagates.
    init(_ error: Error) {
        self = error as? ComparisonBuildFailure ?? .insertionFailed(error.localizedDescription)
    }

    /// Stable, low-cardinality label for the log line and the DEBUG timeline.
    var probeReason: String {
        switch self {
        case .fileMissing(let side): return "file_missing_\(side.probeLabel)"
        case .noVideoTrack(let side): return "no_video_track_\(side.probeLabel)"
        case .swingRangeOutsideVideo(let side): return "swing_range_outside_video_\(side.probeLabel)"
        case .alignmentCollapsed: return "alignment_collapsed"
        case .trackAllocationFailed: return "track_allocation_failed"
        case .insertionFailed: return "insertion_failed"
        }
    }

    /// The underlying framework message where there is one. Logged, never shown.
    var diagnosticDetail: String? {
        guard case .insertionFailed(let message) = self else { return nil }
        return message
    }
}

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

    private var frameDuration: TimeInterval { 1.0 / Double(targetFrameRate) }

    /// One source asset's tracks, loaded ONCE up front via the async
    /// track-loading API so the insertion helpers never fall back to the
    /// deprecated synchronous `tracks(withMediaType:)` parse.
    private struct SourceTracks {
        /// Retained ON PURPOSE, and it is the whole reason this type exists rather than a
        /// bare pair of tracks: `AVAssetTrack.asset` is a WEAK back-reference. A track
        /// whose asset has been released is still a live object that answers questions
        /// about itself, but `insertTimeRange(_:of:at:)` fails against it with
        /// AVFoundationErrorDomain -11800 (-12780) — every insert, including a perfectly
        /// in-range one. Dropping the asset here made every single comparison fail.
        let asset: AVURLAsset
        let video: AVAssetTrack
        let audio: AVAssetTrack?
        /// The video track's real extent, so a marker asking for footage the file does not
        /// contain can be trimmed to what exists.
        let timeRange: CMTimeRange

        /// `range` intersected with the footage that actually exists, or nil when less than
        /// `minimumDuration` of it survives.
        ///
        /// AVFoundation does NOT reject an overrunning source range — it pads the
        /// composition out to the length asked for — so an unclamped marker buys black tail
        /// and a misplaced impact instead of an error. A range with nothing left inside the
        /// track has to fail, though: a zero-length insert throws.
        func footage(for range: SwingTimeRange, minimumDuration: TimeInterval) -> SwingTimeRange? {
            let lower = max(0, CMTimeGetSeconds(timeRange.start))
            let upper = CMTimeGetSeconds(timeRange.end)
            let start = min(max(range.startTime, lower), upper)
            let end = min(max(range.endTime, start), upper)
            guard end - start >= minimumDuration else { return nil }
            return SwingTimeRange(
                startTime: start,
                contactTime: min(max(range.contactTime, start), end),
                endTime: end
            )
        }
    }

    /// Main-actor bound because SwingVideo is a SwiftData model; the awaited
    /// track loads suspend (never block) the main actor while AVFoundation
    /// parses the movies on its own queues.
    @MainActor
    func build(
        video1: SwingVideo, video2: SwingVideo,
        swing1: SwingTimeRange, swing2: SwingTimeRange,
        mode: ComparisonMode, isSwapped: Bool, stackedOpacity: CGFloat
    ) async -> Result<ComparisonComposition, ComparisonBuildFailure> {
        do {
            // Both sources stay in scope for the whole build — see SourceTracks.asset.
            let source1 = try await loadSource(video1, side: .first)
            let source2 = try await loadSource(video2, side: .second)
            let range1 = try footage(of: source1, for: swing1, side: .first)
            let range2 = try footage(of: source2, for: swing2, side: .second)
            guard mode != .sequential else {
                let sequential = try buildSequential(source1, source2, swing1: range1, swing2: range2, isSwapped: isSwapped)
                return .success(sequential)
            }
            let synced = try buildSynced(source1, source2, swing1: range1, swing2: range2,
                                         mode: mode, isSwapped: isSwapped, stackedOpacity: stackedOpacity)
            return .success(synced)
        } catch {
            return .failure(ComparisonBuildFailure(error))
        }
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
        _ source1: SourceTracks, _ source2: SourceTracks,
        swing1: SwingTimeRange, swing2: SwingTimeRange,
        mode: ComparisonMode, isSwapped: Bool, stackedOpacity: CGFloat
    ) throws -> ComparisonComposition {
        let timing = SyncedTiming(swing1: swing1, swing2: swing2)
        guard timing.totalDuration > 0 else { throw ComparisonBuildFailure.alignmentCollapsed }
        let composition = AVMutableComposition()
        let tracks = try insertSyncedTracks(source1, source2, swing1: swing1, swing2: swing2, timing: timing, into: composition)
        let strategy = mode.layoutStrategy
        let layouts = syncedLayouts(tracks: tracks, strategy: strategy, isSwapped: isSwapped, stackedOpacity: stackedOpacity)
        let videoComposition = makeVideoComposition(canvas: strategy.canvasSize(for: tracks), totalDuration: timing.totalDuration, layouts: layouts)
        return assembleComposition(composition: composition, videoComposition: videoComposition,
                                   totalDuration: timing.totalDuration, contactTime: timing.impactTime, tracks: tracks)
    }

    private func insertSyncedTracks(
        _ source1: SourceTracks, _ source2: SourceTracks,
        swing1: SwingTimeRange, swing2: SwingTimeRange,
        timing: SyncedTiming, into composition: AVMutableComposition
    ) throws -> [AVCompositionTrack] {
        let videoTrack1 = try insertSyncedVideoTrack(source1.video, swing: swing1, preGap: timing.preGap1, postGap: timing.postGap1, into: composition)
        let videoTrack2 = try insertSyncedVideoTrack(source2.video, swing: swing2, preGap: timing.preGap2, postGap: timing.postGap2, into: composition)
        insertAudio(source1.audio, range: swing1, into: composition, atCompositionTime: timing.preGap1)
        insertAudio(source2.audio, range: swing2, into: composition, atCompositionTime: timing.preGap2)
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
        _ source1: SourceTracks, _ source2: SourceTracks,
        swing1: SwingTimeRange, swing2: SwingTimeRange, isSwapped: Bool
    ) throws -> ComparisonComposition {
        let composition = AVMutableComposition()
        let (firstSource, firstRange) = isSwapped ? (source2, swing2) : (source1, swing1)
        let (secondSource, secondRange) = isSwapped ? (source1, swing1) : (source2, swing2)
        let tracks = try insertSequentialTracks(
            firstSource, firstRange: firstRange, secondSource, secondRange: secondRange, into: composition
        )
        let totalDuration = firstRange.duration + secondRange.duration
        let strategy = SequentialLayout()
        let canvas = strategy.canvasSize(for: tracks)
        let layouts = sequentialLayouts(tracks: tracks, canvas: canvas, firstDuration: firstRange.duration, secondDuration: secondRange.duration)
        let videoComposition = makeVideoComposition(canvas: canvas, totalDuration: totalDuration, layouts: layouts)
        return assembleComposition(composition: composition, videoComposition: videoComposition,
                                   totalDuration: totalDuration, contactTime: nil, tracks: tracks)
    }

    private func insertSequentialTracks(
        _ firstSource: SourceTracks, firstRange: SwingTimeRange,
        _ secondSource: SourceTracks, secondRange: SwingTimeRange,
        into composition: AVMutableComposition
    ) throws -> [AVCompositionTrack] {
        let videoTrack1 = try insertVideo(firstSource.video, range: firstRange, into: composition, atCompositionTime: 0)
        let videoTrack2 = try insertVideo(secondSource.video, range: secondRange, into: composition, atCompositionTime: firstRange.duration)
        insertAudio(firstSource.audio, range: firstRange, into: composition, atCompositionTime: 0)
        insertAudio(secondSource.audio, range: secondRange, into: composition, atCompositionTime: firstRange.duration)
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
            contactTime: contactTime, frameDuration: frameDuration,
            videoTracks: tracks
        )
    }

    // MARK: - Track Insertion

    private func loadSource(_ video: SwingVideo, side: ComparisonSide) async throws -> SourceTracks {
        guard let url = video.validLocalURL else { throw ComparisonBuildFailure.fileMissing(side) }
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
              let timeRange = try? await videoTrack.load(.timeRange) else {
            throw ComparisonBuildFailure.noVideoTrack(side)
        }
        let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first
        return SourceTracks(asset: asset, video: videoTrack, audio: audioTrack, timeRange: timeRange)
    }

    private func footage(of source: SourceTracks, for range: SwingTimeRange, side: ComparisonSide) throws -> SwingTimeRange {
        guard let usable = source.footage(for: range, minimumDuration: frameDuration) else {
            throw ComparisonBuildFailure.swingRangeOutsideVideo(side)
        }
        return usable
    }

    private func insertVideo(
        _ sourceTrack: AVAssetTrack, range: SwingTimeRange,
        into composition: AVMutableComposition, atCompositionTime time: TimeInterval
    ) throws -> AVCompositionTrack {
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ComparisonBuildFailure.trackAllocationFailed
        }
        let sourceRange = cmTimeRange(from: range)
        // Propagated, not swallowed: a failed insert used to leave an EMPTY track behind
        // and play as black rather than saying anything.
        try track.insertTimeRange(sourceRange, of: sourceTrack, at: CMTime(seconds: time, preferredTimescale: 600))
        track.preferredTransform = sourceTrack.preferredTransform
        return track
    }

    /// Adapter from playback's (SwingTimeRange, TimeInterval) inputs to the
    /// shared FreezeFrameInserter's (CMTimeRange, CMTime) interface.
    private func insertSyncedVideoTrack(
        _ sourceTrack: AVAssetTrack, swing: SwingTimeRange,
        preGap: TimeInterval, postGap: TimeInterval,
        into composition: AVMutableComposition
    ) throws -> AVCompositionTrack {
        guard let track = try FreezeFrameInserter.insertVideo(
            sourceTrack: sourceTrack, sourceRange: cmTimeRange(from: swing),
            preGap: CMTime(seconds: preGap, preferredTimescale: 600),
            postGap: CMTime(seconds: postGap, preferredTimescale: 600),
            targetFrameRate: targetFrameRate, into: composition
        ) else {
            throw ComparisonBuildFailure.trackAllocationFailed
        }
        return track
    }

    private func insertAudio(
        _ sourceTrack: AVAssetTrack?, range: SwingTimeRange,
        into composition: AVMutableComposition, atCompositionTime time: TimeInterval
    ) {
        guard let sourceTrack,
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
