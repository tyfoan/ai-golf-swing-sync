//
//  CellConfiguration.swift
//  golf-sync-swing
//
//  One cell in the export composition: where it sits on the canvas, the composition
//  track it pulls pixels from, and how the user framed it in the editor.
//
//  Simplified port of video-collage's CellConfiguration: video-only (no photos,
//  no thumbnails, no audio routing — audio is on its own composition track and
//  plays in parallel).
//

import Foundation
import CoreGraphics
import AVFoundation

nonisolated struct CellConfiguration {

    /// Cell's position and size in the export render canvas (UIKit-style top-left origin).
    let cellRect: CGRect

    /// The track this cell draws and how its pixels are oriented.
    let source: CellSource

    /// The pinch and pan the user set on this swing's editor tile.
    let framing: VideoTransform

    /// The rounding of the swing's card in canvas pixels, before the user's zoom.
    let cornerRadius: CGFloat

    var videoTrackID: CMPersistentTrackID { source.trackID }
    var naturalSize: CGSize { source.naturalSize }
    var preferredTransform: CGAffineTransform { source.preferredTransform }

    /// User pinch zoom level (1.0 = identity).
    var userScale: CGFloat { framing.scale }

    /// User pan offset in editor-tile points (PRE-scale; visible shift = offset × userScale).
    var userOffset: CGPoint { framing.offset }

    /// Editor tile size in points where the user did the gestures. The compositor
    /// uses this to map preview-space pan into export pixels.
    var containerSize: CGSize { framing.containerSize }

    var displaySize: CGSize {
        naturalSize.applying(preferredTransform)
    }

    var aspectFitScale: CGFloat {
        let rotated = displaySize.absoluteSize()
        guard rotated.width > 0, rotated.height > 0 else { return 1 }
        return min(cellRect.width / rotated.width, cellRect.height / rotated.height)
    }

    var baseScale: CGFloat { aspectFitScale }
    var finalScale: CGFloat { baseScale * userScale }
}

/// A composition video track as the compositor reads it.
nonisolated struct CellSource {
    let trackID: CMPersistentTrackID
    /// Source video natural size (pre-rotation).
    let naturalSize: CGSize
    /// Source video rotation transform.
    let preferredTransform: CGAffineTransform
}

extension CGSize {
    nonisolated func absoluteSize() -> CGSize {
        CGSize(width: Swift.abs(width), height: Swift.abs(height))
    }
}
