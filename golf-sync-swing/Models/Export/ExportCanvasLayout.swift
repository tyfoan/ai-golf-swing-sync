//
//  ExportCanvasLayout.swift
//  golf-sync-swing
//
//  Where the two swings sit on an export canvas: two equal cells with a thin seam
//  between them, or both on the whole canvas. The editor asks in points and the exporter
//  in pixels, so a tile on screen and its cell in the file always have the same
//  proportions — the pan and zoom framed in one land exactly in the other.
//

import CoreGraphics

nonisolated struct ExportCanvasLayout: Equatable {
    let canvas: CGSize
    let arrangement: VideoArrangement

    /// The seam between split cells, as a share of the canvas's short side.
    static let seamFraction: CGFloat = 0.012

    var seam: CGFloat {
        min(canvas.width, canvas.height) * Self.seamFraction
    }

    /// One rectangle per swing, in export order, with a top-left origin.
    var cellRects: [CGRect] {
        switch arrangement {
        case .horizontal: return horizontalCells
        case .vertical: return verticalCells
        case .overlaid: return [wholeCanvas, wholeCanvas]
        }
    }

    private var wholeCanvas: CGRect {
        CGRect(origin: .zero, size: canvas)
    }

    private var horizontalCells: [CGRect] {
        let width = (canvas.width - seam) / 2
        return [
            CGRect(x: 0, y: 0, width: width, height: canvas.height),
            CGRect(x: width + seam, y: 0, width: width, height: canvas.height)
        ]
    }

    private var verticalCells: [CGRect] {
        let height = (canvas.height - seam) / 2
        return [
            CGRect(x: 0, y: 0, width: canvas.width, height: height),
            CGRect(x: 0, y: height + seam, width: canvas.width, height: height)
        ]
    }
}
