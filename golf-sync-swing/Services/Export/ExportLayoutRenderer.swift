//
//  ExportLayoutRenderer.swift
//  golf-sync-swing
//
//  Pure render math: maps editor transforms (preview-space points) to
//  AVMutableVideoCompositionLayerInstruction transforms (export pixels).
//
//  Math lifted from VideoExportService.calculateTransform() (aspect-fit + center)
//  and extended with user scale + pan from the editor.
//

import CoreGraphics
import AVFoundation

enum ExportLayoutRenderer {

    /// Returns the CGAffineTransform to feed into `AVMutableVideoCompositionLayerInstruction.setTransform`
    /// for one video, accounting for: rotation (preferredTransform), aspect-fit into the cell,
    /// user-applied pinch (scale), and user-applied pan (offset).
    static func transform(
        videoSize: CGSize,
        preferredTransform: CGAffineTransform,
        cellRect: CGRect,
        userTransform: VideoTransform
    ) -> CGAffineTransform {
        let displaySize = videoSize.applying(preferredTransform)
        let videoWidth = abs(displaySize.width)
        let videoHeight = abs(displaySize.height)

        let aspectFitScale = min(cellRect.width / videoWidth, cellRect.height / videoHeight)
        let totalScale = aspectFitScale * userTransform.scale

        var rotationOnly = preferredTransform
        rotationOnly.tx = 0
        rotationOnly.ty = 0

        var transform = CGAffineTransform.identity
        transform = transform.concatenating(rotationOnly)
        transform = transform.scaledBy(x: totalScale, y: totalScale)

        let bounding = boundingBox(of: videoSize, transformed: transform)

        let panInExport = panInExportPixels(
            userOffset: userTransform.offset,
            userScale: userTransform.scale,
            containerSize: userTransform.containerSize,
            cellRect: cellRect
        )

        let targetCenterX = cellRect.midX + panInExport.x
        let targetCenterY = cellRect.midY + panInExport.y

        transform.tx += targetCenterX - bounding.midX
        transform.ty += targetCenterY - bounding.midY

        return transform
    }

    private static func boundingBox(of videoSize: CGSize, transformed: CGAffineTransform) -> CGRect {
        let corners = [
            CGPoint.zero,
            CGPoint(x: videoSize.width, y: 0),
            CGPoint(x: videoSize.width, y: videoSize.height),
            CGPoint(x: 0, y: videoSize.height)
        ].map { $0.applying(transformed) }

        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// `userOffset` is stored PRE-scale. SwiftUI applies `.offset()` before
    /// `.scaleEffect()`, so the visible shift in the editor is `offset × scale`.
    /// We multiply by `userScale` here so the export reproduces the same
    /// visible shift the user saw. Matches video-collage's CollageVideoCompositor:
    ///     panX = offset.x × scale × (mediaInExport / mediaInScreen).
    /// We use the cell-to-container ratio in place of the media-size ratio,
    /// which is equivalent for aspect-fit content centered in the cell.
    private static func panInExportPixels(
        userOffset: CGPoint,
        userScale: CGFloat,
        containerSize: CGSize,
        cellRect: CGRect
    ) -> CGPoint {
        guard containerSize.width > 0 && containerSize.height > 0 else { return .zero }
        let scaleX = cellRect.width / containerSize.width
        let scaleY = cellRect.height / containerSize.height
        return CGPoint(
            x: userOffset.x * userScale * scaleX,
            y: userOffset.y * userScale * scaleY
        )
    }
}
