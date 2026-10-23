//
//  CellBackdrop.swift
//  golf-sync-swing
//
//  The fill behind a fitted swing in an exported cell: the swing itself, scaled to cover
//  the cell, blurred and dimmed — what the editor shows with `backdropBlurred()`, so the
//  bands around a landscape clip in a portrait cell are never flat black. It ignores the
//  user's pan and zoom, as the editor's does.
//

import CoreImage

nonisolated enum CellBackdrop {
    /// Blurred at an eighth of the cell's size: far cheaper, and a blur hides the scale.
    private static let workingScale: CGFloat = 0.125
    /// Gaussian sigma at the working scale — about 5% of a 1080-pixel cell once scaled up.
    private static let blurSigma: Double = 7
    /// Brightness kept, so the fill stays well below the swing in front of it.
    private static let dimming: CGFloat = 0.47
    private static let saturation: Double = 0.75

    /// `oriented` is the source frame upright; `cell` is in Core Image (bottom-up) space.
    static func image(from oriented: CIImage, filling cell: CGRect) -> CIImage {
        let extent = oriented.extent
        guard extent.width > 0, extent.height > 0 else { return CIImage.empty() }
        let cover = max(cell.width / extent.width, cell.height / extent.height)
        let blurred = blurredCopy(of: oriented, at: cover * workingScale)
            .transformed(by: CGAffineTransform(scaleX: 1 / workingScale, y: 1 / workingScale))
        return dimmed(centred(blurred, over: cell, coverSize: extent.size, scale: cover))
            .cropped(to: cell)
    }

    private static func blurredCopy(of image: CIImage, at scale: CGFloat) -> CIImage {
        image
            .transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: blurSigma)
    }

    /// Moves the scaled-up copy, whose covering frame starts at the origin, over the cell.
    private static func centred(_ image: CIImage, over cell: CGRect, coverSize: CGSize, scale: CGFloat) -> CIImage {
        let x = cell.midX - coverSize.width * scale / 2
        let y = cell.midY - coverSize.height * scale / 2
        return image.transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    private static func dimmed(_ image: CIImage) -> CIImage {
        image
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: dimming, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: dimming, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: dimming, w: 0)
            ])
    }
}
