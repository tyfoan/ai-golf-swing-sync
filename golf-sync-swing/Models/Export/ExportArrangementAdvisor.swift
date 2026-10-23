//
//  ExportArrangementAdvisor.swift
//  golf-sync-swing
//
//  Splits an export canvas the way that shows the SMALLER of the two swings biggest —
//  the rule the comparison itself opens with. Two landscape pro swings on a square
//  canvas go one above the other, two portrait takes side by side. When both splits
//  are about as good, the comparison's own arrangement stands. Overlaid modes are never
//  split.
//

import CoreGraphics

nonisolated struct ExportArrangementAdvisor {
    /// Width over height of each swing as it displays.
    let aspects: [CGFloat]

    /// How much better one split must be before it overrides the comparison's own.
    private let decisiveMargin: CGFloat = 0.05

    func arrangement(for preferred: VideoArrangement, canvas: CGSize) -> VideoArrangement {
        guard preferred != .overlaid else { return .overlaid }
        let sideBySide = smallestFittedArea(in: ExportCanvasLayout(canvas: canvas, arrangement: .horizontal))
        let stacked = smallestFittedArea(in: ExportCanvasLayout(canvas: canvas, arrangement: .vertical))
        guard abs(sideBySide - stacked) > decisiveMargin * max(sideBySide, stacked) else { return preferred }
        return sideBySide > stacked ? .horizontal : .vertical
    }

    private func smallestFittedArea(in layout: ExportCanvasLayout) -> CGFloat {
        zip(aspects, layout.cellRects).map(fittedArea).min() ?? 0
    }

    private func fittedArea(aspect: CGFloat, cell: CGRect) -> CGFloat {
        guard aspect > 0, cell.height > 0 else { return 0 }
        let width = min(cell.width, cell.height * aspect)
        return width * width / aspect
    }
}
