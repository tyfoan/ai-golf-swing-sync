//
//  CellRenderer.swift
//  golf-sync-swing
//
//  Turns one source frame into one cell of an export frame: the swing upright, scaled
//  and panned the way the user framed its editor tile, and cut to its card.
//
//  ⚠️ The pan mapping mirrors ZoomableVideoTile, which renders `.offset()` BEFORE
//  `.scaleEffect()`: the visible shift is `offset × scale` in tile points, carried into
//  export pixels by `mediaInExport / mediaInScreen`. Change neither side alone.
//

import CoreImage
import CoreVideo

nonisolated struct CellRenderer {
    let cell: CellConfiguration
    let canvasSize: CGSize

    /// The cell's rectangle in Core Image's bottom-up space.
    var flippedCellRect: CGRect {
        let rect = cell.cellRect
        return CGRect(x: rect.minX, y: canvasSize.height - rect.minY - rect.height, width: rect.width, height: rect.height)
    }

    /// Y-flip + rotate + Y-flip dance to bring source pixels into Core Image's
    /// bottom-up coords, with the video's metadata rotation applied.
    func uprightImage(of pixelBuffer: CVPixelBuffer) -> CIImage {
        var rotationOnly = cell.preferredTransform
        rotationOnly.tx = 0
        rotationOnly.ty = 0
        let naturalSize = cell.naturalSize
        var flip = CGAffineTransform(scaleX: 1, y: -1)
        flip = flip.translatedBy(x: 0, y: -naturalSize.height)
        flip = flip.concatenating(rotationOnly)
        let rotatedHeight = abs(naturalSize.applying(rotationOnly).height)
        flip = flip.concatenating(CGAffineTransform(scaleX: 1, y: -1))
        flip = flip.translatedBy(x: 0, y: -rotatedHeight)
        return CIImage(cvPixelBuffer: pixelBuffer).transformed(by: flip)
    }

    /// The swing placed and cut to its card — and to any `outer` frames, such as the
    /// first swing's card under a blended second one. Clipping is why the custom
    /// compositor exists: a zoomed swing must not bleed into its neighbour.
    func video(from upright: CIImage, within outer: [RoundedFrame] = []) -> CIImage {
        let placed = place(upright)
        return CardMask.cut(placed, to: [card(of: placed), cellFrame] + outer).cropped(to: clipRect)
    }

    /// The swing's card where it lands on the canvas.
    func cardFrame(of upright: CIImage) -> RoundedFrame {
        card(of: place(upright))
    }

    /// The swing scaled and centred on the cell plus the user's pan.
    private func place(_ upright: CIImage) -> CIImage {
        let scaled = upright.transformed(by: CGAffineTransform(scaleX: cell.finalScale, y: cell.finalScale))
        let pan = exportPan
        let cellRect = flippedCellRect
        let dx = cellRect.midX + pan.x - scaled.extent.midX
        let dy = cellRect.midY + pan.y - scaled.extent.midY
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))
    }

    /// The swing's own rounded frame, rounded more as it is zoomed — the editor rounds the
    /// tile's video before `.scaleEffect()`.
    private func card(of placed: CIImage) -> RoundedFrame {
        RoundedFrame(rect: placed.extent, radius: cell.cornerRadius * cell.userScale)
    }

    private var cellFrame: RoundedFrame {
        RoundedFrame(rect: clipRect, radius: cell.cornerRadius)
    }

    /// The cell, kept inside the canvas.
    private var clipRect: CGRect {
        let flipped = flippedCellRect
        return CGRect(
            x: max(0, flipped.minX),
            y: max(0, min(flipped.minY, canvasSize.height - 1)),
            width: min(flipped.width, canvasSize.width),
            height: min(flipped.height, canvasSize.height)
        )
    }

    /// The editor's pan in export pixels, Y pointing up.
    private var exportPan: CGPoint {
        let screen = mediaSize(atScale: screenBaseScale)
        let export = mediaSize(atScale: cell.baseScale)
        let contentX = cell.userOffset.x * cell.userScale
        let contentY = cell.userOffset.y * cell.userScale
        return CGPoint(
            x: screen.width > 0 ? contentX * (export.width / screen.width) : 0,
            y: screen.height > 0 ? -contentY * (export.height / screen.height) : 0
        )
    }

    /// How the swing was fitted into its editor tile — the export's own fit when the
    /// tile's size never arrived.
    private var screenBaseScale: CGFloat {
        let media = cell.displaySize.absoluteSize()
        let container = cell.containerSize
        guard container.width > 0, container.height > 0, media.width > 0, media.height > 0 else {
            return cell.baseScale
        }
        return min(container.width / media.width, container.height / media.height)
    }

    private func mediaSize(atScale scale: CGFloat) -> CGSize {
        let media = cell.displaySize.absoluteSize()
        return CGSize(width: media.width * scale, height: media.height * scale)
    }
}
