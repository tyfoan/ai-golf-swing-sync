//
//  FreezeFrameInserter.swift
//  golf-sync-swing
//
//  Shared utility for inserting a video source into an AVMutableComposition
//  with first/last frame freezes covering pre/post time gaps.
//
//  Used by both:
//  - ComparisonCompositionBuilder (in-app playback)
//  - VideoExportService (exported MP4)
//
//  so the exported file matches what the user sees in the app: held address
//  pose during one clip's lead-in, held finish pose during one clip's
//  follow-through — no black bars during impact-alignment asymmetry.
//
//  Mechanism: insert a single-frame source range, then scaleTimeRange to
//  stretch it across the gap. AVFoundation holds (does not interpolate)
//  the frame for the stretched duration.
//

import AVFoundation
import CoreMedia

enum FreezeFrameInserter {

    static let defaultTargetFrameRate: Int32 = 30

    /// Adds a video composition track to `composition`, fills it with
    /// `sourceRange` from `sourceTrack` plus optional held first/last frame
    /// slices spanning `preGap` and `postGap`. Returns the new composition
    /// track, or nil if track allocation failed.
    ///
    /// Gaps shorter than two frames are skipped — too short to perceive and
    /// a stretched single-frame can flicker on some hardware.
    @discardableResult
    static func insertVideo(
        sourceTrack: AVAssetTrack,
        sourceRange: CMTimeRange,
        preGap: CMTime = .zero,
        postGap: CMTime = .zero,
        targetFrameRate: Int32 = defaultTargetFrameRate,
        into composition: AVMutableComposition
    ) throws -> AVMutableCompositionTrack? {
        guard let track = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }

        let oneFrame = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
        let twoFrames = CMTime(value: 2, timescale: CMTimeScale(targetFrameRate))
        var cursor: CMTime = .zero

        if CMTimeCompare(preGap, twoFrames) >= 0 {
            let freezeSrc = CMTimeRange(start: sourceRange.start, duration: oneFrame)
            try track.insertTimeRange(freezeSrc, of: sourceTrack, at: cursor)
            track.scaleTimeRange(CMTimeRange(start: cursor, duration: oneFrame), toDuration: preGap)
            cursor = cursor + preGap
        }

        try track.insertTimeRange(sourceRange, of: sourceTrack, at: cursor)
        cursor = cursor + sourceRange.duration

        if CMTimeCompare(postGap, twoFrames) >= 0,
           CMTimeCompare(sourceRange.duration, oneFrame) >= 0 {
            let lastFrameStart = sourceRange.start + sourceRange.duration - oneFrame
            let freezeSrc = CMTimeRange(start: lastFrameStart, duration: oneFrame)
            try track.insertTimeRange(freezeSrc, of: sourceTrack, at: cursor)
            track.scaleTimeRange(CMTimeRange(start: cursor, duration: oneFrame), toDuration: postGap)
        }

        track.preferredTransform = sourceTrack.preferredTransform
        return track
    }
}
