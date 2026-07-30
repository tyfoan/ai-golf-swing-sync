//
//  RingFrameDecoder.swift
//  golf-sync-swing
//
//  The read side of `SwingFrameBuffer`: one of its JPEGs, decoded into a bitmap the render server
//  can draw without touching it again.
//
//  WHY IT IS A TYPE AND NOT TWO LINES IN A VIEW
//  -------------------------------------------
//  It was two lines in a view — `UIImage(data:)?.preparingForDisplay()` on
//  `LiveRingFrameView` — and that was affordable only while every ring frame was small. The ring
//  now stores frames at the CAMERA's own resolution, and a decoded 1080x1920 bitmap is 8.3MB
//  (MEASURED arithmetic: 1080 x 1920 x 4B). Three surfaces draw those frames, and one of them —
//  the 120x160 picture-in-picture tile — draws them into 360x480 device pixels. Decoding a full
//  frame for that tile spends 8.3MB to display 0.5MB of it.
//
//  So the size a frame is DRAWN at became a parameter of decoding it, and that made a type: which
//  bitmap size a box deserves is one decision, taken in one place, by `longEdge(drawnIn:scale:)`,
//  and both capture surfaces ask it rather than each carrying a number that could drift from the
//  layout.
//
//  ONE DECODE PATH, AT EVERY SIZE
//  ------------------------------
//  There used to be two, and the stored-size one cost a bitmap it did not need — see `decoded`.
//  Everything now goes through ImageIO at the size the box draws, which is one allocation whatever
//  that size is.
//
//  WHY THE SIZES HALVE
//  -------------------
//  A JPEG is stored as 8x8 DCT blocks, and ImageIO can reconstruct those blocks at 1/2, 1/4 or 1/8
//  scale for a fraction of the work of a full decode plus a resample — the decoder never
//  materialises the pixels it is going to throw away. `longEdge` therefore quantises to the stored
//  edge halved: at 1920 stored, a tile asking for 480 gets a 1/4-scale decode, which is ~1/16 the
//  bitmap and (ESTIMATED, from the block arithmetic) a small fraction of the decode.
//
//  `nonisolated static` + `@concurrent`: under `NonisolatedNonsendingByDefault` a plain
//  `nonisolated async` function runs on its CALLER's actor — main — and JPEG decompression on the
//  main thread over a live capture session is the one thing this must not do.
//

// Explicit, module by module: the target builds with
// `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`, so re-exports do not count.
import CoreGraphics
import Foundation
import ImageIO
import UIKit

nonisolated struct RingFrameDecoder {

    /// Never below this, whatever a box asks for. A zero-sized box — a surface measured before its
    /// first layout — would otherwise ask for a zero-pixel image, and the halving below would have
    /// no floor to stop at.
    private static let minimumLongEdge = 240

    /// The bitmap long edge, in pixels, that a frame drawn in `size` at `scale` deserves: the
    /// stored edge halved as many times as still covers the box.
    ///
    /// `max(size)` and not the fitted image's own long edge, because the frames are letterboxed
    /// `.fit` into whatever box they are given — in a portrait box the image's long edge IS the
    /// box's, and in a landscape one this over-estimates, which spends bytes rather than sharpness.
    /// Erring toward more pixels is the right direction for the one number the user complained
    /// about.
    static func longEdge(drawnIn size: CGSize, scale: CGFloat) -> Int {
        let atLeast = max(Int((max(size.width, size.height) * max(1, scale)).rounded(.up)), minimumLongEdge)
        var edge = SwingFrameBuffer.storedLongEdge
        while edge / 2 >= atLeast { edge /= 2 }
        return edge
    }

    /// One ring frame, decoded and ready to draw. **One route, at every size**, and the removal of
    /// the second one is worth a paragraph because it is easy to sell as the wrong thing.
    ///
    /// At exactly the stored size this used to take a short cut: `UIImage(data:)` is lazy, so
    /// `preparingForDisplay()` was described as decoding it "in a SINGLE allocation". That is not
    /// what the API does. It decodes the JPEG and then REDRAWS the result into a second,
    /// display-format bitmap — so the full-screen replay paid two 8.3MB allocations and one
    /// full-frame draw for every frame it showed, 15 times a second, for as long as a replay was up
    /// (ESTIMATED from the API's contract, not timed; the allocations would MEASURE it). Asking
    /// ImageIO for the size the box draws produces exactly one bitmap however that size compares
    /// with the stored one.
    ///
    /// **It is NOT a byte saving on the full screen and must not be read as one.** `longEdge` is
    /// quantised down from `SwingFrameBuffer.storedLongEdge`, so the full-screen cover still asks
    /// for 1920 and still gets a 1080x1920, 8.3MB bitmap — the box it is drawn in is 1179x2096
    /// device pixels, which is LARGER than anything the ring holds, so there is nothing above the
    /// box to leave undecoded. What goes away is the transient double allocation and the redraw.
    /// Below the stored size — every picture-in-picture tile — the pixels above the box were never
    /// materialised in the first place, which is the saving that was always here.
    ///
    /// **The risk this takes, stated so it can be recognised.** `preparingForDisplay()` GUARANTEES a
    /// display-ready bitmap; ImageIO only promises a decoded one. If a device handed back a format
    /// the compositor has to convert, that conversion would land on the main thread at draw time —
    /// at 1920, 15 times a second, worse than what was removed. The reason to expect not:
    /// `SwingFrameBuffer.encode` writes these JPEGs through `CGColorSpaceCreateDeviceRGB()`, so they
    /// decode to 8-bit sRGB, which the compositor takes natively. The symptom would be main-thread
    /// time appearing under `CA::Render` while a replay loops, and the rollback is one line —
    /// `preparingForDisplay()` back on the stored-size case only, accepting the 2x transient again.
    @concurrent
    nonisolated static func decoded(_ jpeg: Data, longEdge: Int) async -> UIImage? {
        bitmap(of: jpeg, longEdge: longEdge)
    }

    /// `kCGImageSourceShouldCacheImmediately` is what keeps the decompression HERE rather than
    /// deferring it to draw time on the main thread — which is the whole reason
    /// `preparingForDisplay()` was ever worth calling on the other path.
    ///
    /// `kCGImageSourceThumbnailMaxPixelSize` does not UPSAMPLE, which is what makes one path safe at
    /// every size: asked for more pixels than the JPEG holds, ImageIO returns the pixels it has.
    /// `longEdge(drawnIn:scale:)` never asks for more anyway, and it stays the only place that
    /// clamps.
    ///
    /// `…FromImageAlways` because a camera JPEG carries no embedded thumbnail to prefer, and
    /// `…WithTransform` so a frame that ever arrives with an orientation tag is decoded upright
    /// rather than sideways. Today none do: `SwingFrameBuffer.encode` writes no orientation,
    /// because the capture connection already rotates the buffer.
    private static func bitmap(of jpeg: Data, longEdge: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        let source = CGImageSourceCreateWithData(jpeg as CFData, sourceOptions as CFDictionary)
        guard let source else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
