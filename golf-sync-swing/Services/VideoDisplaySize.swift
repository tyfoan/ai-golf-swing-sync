//
//  VideoDisplaySize.swift
//  golf-sync-swing
//
//  How a video file displays — its natural size with the rotation applied — read from
//  the track's metadata without decoding a frame. The comparison picks its opening
//  arrangement from it; the single-video player shapes its card to it.
//

import AVFoundation
import CoreGraphics

enum VideoDisplaySize {
    static func of(_ url: URL?) async -> CGSize? {
        guard let url else { return nil }
        // Held until the loads finish: a track's `asset` is a weak back-reference (see
        // ComparisonCompositionBuilder.SourceTracks).
        let asset = AVURLAsset(url: url)
        defer { withExtendedLifetime(asset) {} }
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let loaded = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let rect = CGRect(origin: .zero, size: loaded.0).applying(loaded.1)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    /// Width over height, or nil when the file has no readable video track.
    static func aspectRatio(of url: URL?) async -> CGFloat? {
        guard let size = await of(url), size.width > 0, size.height > 0 else { return nil }
        return size.width / size.height
    }
}
