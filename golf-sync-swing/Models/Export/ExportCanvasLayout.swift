//
//  ExportCanvasLayout.swift
//  golf-sync-swing
//
//  Where the two swings sit on an export canvas: two equal cells, or both in one, inset
//  from the edges and from each other so each swing reads as a card on the cream
//  canvas, as on the comparison screen. The editor asks in points and the exporter in
//  pixels, so a tile on screen and its cell in the file always have the same
//  proportions — the pan and zoom framed in one land exactly in the other.
//

import CoreGraphics

nonisolated struct ExportCanvasLayout: Equatable {
    let canvas: CGSize
    let arrangement: VideoArrangement

    /// The cream around and between the cells, as a share of the canvas's short side.
    static let spacingFraction: CGFloat = 0.04
    /// The rounding of a swing's card, as a share of the canvas's short side.
    static let cornerFraction: CGFloat = 0.035

    var spacing: CGFloat { shortSide * Self.spacingFraction }
    var cornerRadius: CGFloat { shortSide * Self.cornerFraction }

    /// One rectangle per swing, in export order, with a top-left origin.
    var cellRects: [CGRect] {
        switch arrangement {
        case .horizontal: return horizontalCells
        case .vertical: return verticalCells
        case .overlaid: return [content, content]
        }
    }

    private var shortSide: CGFloat {
        min(canvas.width, canvas.height)
    }

    /// The canvas less its cream margin.
    private var content: CGRect {
        CGRect(origin: .zero, size: canvas).insetBy(dx: spacing, dy: spacing)
    }

    private var horizontalCells: [CGRect] {
        let width = (content.width - spacing) / 2
        return [
            CGRect(x: content.minX, y: content.minY, width: width, height: content.height),
            CGRect(x: content.minX + width + spacing, y: content.minY, width: width, height: content.height)
        ]
    }

    private var verticalCells: [CGRect] {
        let height = (content.height - spacing) / 2
        return [
            CGRect(x: content.minX, y: content.minY, width: content.width, height: height),
            CGRect(x: content.minX, y: content.minY + height + spacing, width: content.width, height: height)
        ]
    }
}
