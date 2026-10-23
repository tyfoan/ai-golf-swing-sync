//
//  LayoutSizing.swift
//  golf-sync-swing
//
//  Shared geometry for the comparison composition's frame: how a track displays, and
//  the cap that keeps the frame cheap to render.
//

import AVFoundation
import CoreGraphics

nonisolated enum LayoutSizing {
    static let maxRenderEdge: CGFloat = 1920

    static func displayedSize(of track: AVCompositionTrack) -> CGSize {
        let raw = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
        return CGSize(width: abs(raw.width), height: abs(raw.height))
    }

    /// The uniform scale that brings a canvas's longest edge under the render cap.
    static func capScale(for canvas: CGSize) -> CGFloat {
        let longest = max(canvas.width, canvas.height)
        return longest > maxRenderEdge ? maxRenderEdge / longest : 1.0
    }

    /// Even dimensions — hardware video codecs reject an odd render size.
    static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(width: even(size.width), height: even(size.height))
    }

    private static func even(_ value: CGFloat) -> CGFloat {
        max(2, round(value / 2) * 2)
    }
}
