//
//  CardMask.swift
//  golf-sync-swing
//
//  Cuts a swing to its card in an export frame: the swing's own rounded frame, kept
//  inside its cell's rounded frame — and a blended Stacked swing inside the first
//  swing's card too. These are the shapes the editor clips its tiles to, so the file
//  looks like the editor. Everything outside is left clear for the cream canvas.
//

import CoreImage
import CoreImage.CIFilterBuiltins

nonisolated enum CardMask {
    /// Keeps the image only where every frame covers it.
    static func cut(_ image: CIImage, to frames: [RoundedFrame]) -> CIImage {
        guard let first = frames.first else { return image }
        let mask = frames.dropFirst().reduce(shape(of: first)) { mask, frame in
            mask.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: shape(of: frame)])
        }
        return image.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask
        ])
    }

    /// Opaque white inside the frame, clear outside.
    private static func shape(of frame: RoundedFrame) -> CIImage {
        let generator = CIFilter.roundedRectangleGenerator()
        generator.extent = frame.rect
        generator.radius = Float(min(frame.radius, frame.rect.width / 2, frame.rect.height / 2))
        generator.color = .white
        return generator.outputImage ?? .empty()
    }
}

/// A rectangle with rounded corners, in Core Image's bottom-up space.
nonisolated struct RoundedFrame {
    let rect: CGRect
    let radius: CGFloat
}
