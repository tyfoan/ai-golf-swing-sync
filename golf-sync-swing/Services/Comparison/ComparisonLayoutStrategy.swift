//
//  ComparisonLayoutStrategy.swift
//  golf-sync-swing
//
//  Per-mode spatial layout for the comparison composition. Each strategy
//  knows: how big the render canvas should be for a pair of tracks, where
//  each track sits within it, what opacity each gets, and whether
//  transitioning to/from this mode requires a structural rebuild of the
//  composition (as opposed to a cheap videoComposition swap).
//
//  Extracted to replace four parallel mode switches in
//  ComparisonCompositionBuilder (renderSize, slots, opacity) plus the
//  one in ComparisonViewModel.onModeChanged. Dispatch is now polymorphic.
//

import AVFoundation
import UIKit

protocol ComparisonLayoutStrategy {
    func canvasSize(for tracks: [AVCompositionTrack]) -> CGSize
    func slots(in canvas: CGSize, isSwapped: Bool) -> [CGRect]
    func opacity(forIndex index: Int, stackedOpacity: CGFloat) -> CGFloat
    /// True when transitioning to/from this layout changes the composition's
    /// track time offsets — i.e. the playback view model can't just swap
    /// the videoComposition, it must rebuild the AVPlayerItem.
    var requiresStructuralRebuild: Bool { get }
}

extension ComparisonMode {
    var layoutStrategy: ComparisonLayoutStrategy {
        switch self {
        case .sideBySide: return SideBySideLayout()
        case .topBottom:  return TopBottomLayout()
        case .stacked:    return StackedLayout()
        case .sequential: return SequentialLayout()
        }
    }
}

// MARK: - Concrete Strategies

struct SideBySideLayout: ComparisonLayoutStrategy {
    var requiresStructuralRebuild: Bool { false }

    func canvasSize(for tracks: [AVCompositionTrack]) -> CGSize {
        let sizes = tracks.map(LayoutSizing.displayedSize)
        return LayoutSizing.cap(width: sizes.map(\.width).reduce(0, +), height: sizes.map(\.height).max() ?? 0)
    }

    func slots(in canvas: CGSize, isSwapped: Bool) -> [CGRect] {
        let left = CGRect(x: 0, y: 0, width: canvas.width / 2, height: canvas.height)
        let right = CGRect(x: canvas.width / 2, y: 0, width: canvas.width / 2, height: canvas.height)
        return isSwapped ? [right, left] : [left, right]
    }

    func opacity(forIndex index: Int, stackedOpacity: CGFloat) -> CGFloat { 1.0 }
}

struct TopBottomLayout: ComparisonLayoutStrategy {
    var requiresStructuralRebuild: Bool { false }

    func canvasSize(for tracks: [AVCompositionTrack]) -> CGSize {
        let sizes = tracks.map(LayoutSizing.displayedSize)
        return LayoutSizing.cap(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).reduce(0, +))
    }

    func slots(in canvas: CGSize, isSwapped: Bool) -> [CGRect] {
        let top = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height / 2)
        let bottom = CGRect(x: 0, y: canvas.height / 2, width: canvas.width, height: canvas.height / 2)
        return isSwapped ? [bottom, top] : [top, bottom]
    }

    func opacity(forIndex index: Int, stackedOpacity: CGFloat) -> CGFloat { 1.0 }
}

struct StackedLayout: ComparisonLayoutStrategy {
    var requiresStructuralRebuild: Bool { false }

    func canvasSize(for tracks: [AVCompositionTrack]) -> CGSize {
        let sizes = tracks.map(LayoutSizing.displayedSize)
        return LayoutSizing.cap(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
    }

    func slots(in canvas: CGSize, isSwapped: Bool) -> [CGRect] {
        let full = CGRect(origin: .zero, size: canvas)
        return [full, full]
    }

    func opacity(forIndex index: Int, stackedOpacity: CGFloat) -> CGFloat {
        index == 1 ? stackedOpacity : 1.0
    }
}

struct SequentialLayout: ComparisonLayoutStrategy {
    /// Sequential changes track insertion offsets (back-to-back vs. parallel),
    /// so VM must full-rebuild when entering or leaving this mode.
    var requiresStructuralRebuild: Bool { true }

    func canvasSize(for tracks: [AVCompositionTrack]) -> CGSize {
        let sizes = tracks.map(LayoutSizing.displayedSize)
        return LayoutSizing.cap(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
    }

    func slots(in canvas: CGSize, isSwapped: Bool) -> [CGRect] {
        let full = CGRect(origin: .zero, size: canvas)
        return [full, full]
    }

    func opacity(forIndex index: Int, stackedOpacity: CGFloat) -> CGFloat { 1.0 }
}

// MARK: - Shared Geometry Helpers

enum LayoutSizing {
    static let maxRenderEdge: CGFloat = 1920

    static func displayedSize(of track: AVCompositionTrack) -> CGSize {
        let raw = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
        return CGSize(width: abs(raw.width), height: abs(raw.height))
    }

    static func cap(width: CGFloat, height: CGFloat) -> CGSize {
        let longest = max(width, height)
        let scale = longest > maxRenderEdge ? maxRenderEdge / longest : 1.0
        return CGSize(width: even(width * scale), height: even(height * scale))
    }

    /// Force even dimensions — hardware video codecs reject odd renderSize.
    private static func even(_ value: CGFloat) -> CGFloat {
        max(2, round(value / 2) * 2)
    }
}
