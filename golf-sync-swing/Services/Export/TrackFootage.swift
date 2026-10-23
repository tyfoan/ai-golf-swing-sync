//
//  TrackFootage.swift
//  golf-sync-swing
//
//  Where a video track's frames actually are. A movie can open with an empty edit —
//  seven of the bundled pro swings start their video 16 ms in — and a source range
//  that starts inside it draws nothing there: a black frame at the start of every
//  comparison loop, and a held first frame black for half its length.
//
//  Shared by playback and export, like FreezeFrameInserter.
//

import AVFoundation
import CoreMedia

enum TrackFootage {
    /// From the track's first real frame to its last: its `timeRange` without any
    /// leading or trailing empty edit.
    ///
    /// Rounded inward to the 1/600 s grid both pipelines build their ranges on, so a
    /// start converted back to CMTime can never land a tick short, inside the edit.
    static func range(of track: AVAssetTrack) async throws -> CMTimeRange {
        let media = try await track.load(.segments).filter { !$0.isEmpty }.map(\.timeMapping.target)
        guard let first = media.first, let last = media.last else { return try await track.load(.timeRange) }
        return CMTimeRange(
            start: CMTimeConvertScale(first.start, timescale: 600, method: .roundTowardPositiveInfinity),
            end: CMTimeConvertScale(last.end, timescale: 600, method: .roundTowardNegativeInfinity)
        )
    }
}
