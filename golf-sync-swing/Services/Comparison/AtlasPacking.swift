//
//  AtlasPacking.swift
//  golf-sync-swing
//
//  Packs the two swings into one composition frame: side by side or one above the
//  other, whichever keeps more of their pixels under the render cap, with a gutter
//  between them so a pane never shows a hairline of its neighbour.
//

import CoreGraphics

nonisolated struct AtlasPacking {
    /// Pixels between the two swings, before the frame is scaled under the cap.
    var gutter: CGFloat = 8

    func atlas(for sizes: [CGSize]) -> ComparisonAtlas {
        let row = packed(sizes, along: .horizontal)
        let column = packed(sizes, along: .vertical)
        let rowKeepsMore = LayoutSizing.capScale(for: row.canvas) >= LayoutSizing.capScale(for: column.canvas)
        return capped(rowKeepsMore ? row : column)
    }

    private func packed(_ sizes: [CGSize], along axis: PackingAxis) -> ComparisonAtlas {
        var origin = CGPoint.zero
        var slots: [CGRect] = []
        for size in sizes {
            slots.append(CGRect(origin: origin, size: size))
            origin = axis.advance(origin, past: size, gutter: gutter)
        }
        return ComparisonAtlas(canvas: extent(of: slots), slots: slots)
    }

    private func extent(of slots: [CGRect]) -> CGSize {
        CGSize(width: slots.map(\.maxX).max() ?? 0, height: slots.map(\.maxY).max() ?? 0)
    }

    private func capped(_ atlas: ComparisonAtlas) -> ComparisonAtlas {
        let scale = LayoutSizing.capScale(for: atlas.canvas)
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        return ComparisonAtlas(
            canvas: LayoutSizing.evenSize(atlas.canvas.applying(transform)),
            slots: atlas.slots.map { $0.applying(transform).integral }
        )
    }
}

nonisolated enum PackingAxis {
    case horizontal, vertical

    func advance(_ origin: CGPoint, past size: CGSize, gutter: CGFloat) -> CGPoint {
        switch self {
        case .horizontal: return CGPoint(x: origin.x + size.width + gutter, y: origin.y)
        case .vertical: return CGPoint(x: origin.x, y: origin.y + size.height + gutter)
        }
    }
}
