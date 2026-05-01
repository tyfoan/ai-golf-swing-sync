//
//  CellConfiguration.swift
//  golf-sync-swing
//
//  One cell in the export composition. Built per export from a VideoTransform
//  + the composition track that the compositor will pull pixels from.
//
//  Simplified port of video-collage's CellConfiguration: video-only (no photos,
//  no thumbnails, no audio routing — audio is on its own composition track and
//  plays in parallel).
//

import Foundation
import CoreGraphics
import AVFoundation

struct CellConfiguration {

    /// Cell's position and size in the export render canvas (UIKit-style top-left origin).
    let cellRect: CGRect

    /// Composition track ID the compositor will request pixel buffers from.
    let videoTrackID: CMPersistentTrackID

    /// Source video natural size (pre-rotation).
    let naturalSize: CGSize

    /// Source video rotation transform.
    let preferredTransform: CGAffineTransform

    /// User pinch zoom level (1.0 = identity).
    let userScale: CGFloat

    /// User pan offset in editor-tile points (PRE-scale; visible shift = offset × userScale).
    let userOffset: CGPoint

    /// Editor tile size in points where the user did the gestures. The compositor
    /// uses this to map preview-space pan into export pixels.
    let containerSize: CGSize

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

extension CGSize {
    func absoluteSize() -> CGSize {
        CGSize(width: Swift.abs(width), height: Swift.abs(height))
    }
}
