//
//  VideoLayoutConfig.swift
//  golf-sync-swing
//
//  The contract between the export editor and the exporter:
//  output aspect ratio + comparison mode + how the canvas is split +
//  per-video transforms (always 2).
//

import CoreGraphics
import Foundation

struct VideoLayoutConfig: Equatable {
    let aspectRatio: ExportAspectRatio
    let mode: ComparisonMode
    let arrangement: VideoArrangement
    let stackedOpacity: CGFloat?    // only used when mode == .stacked
    let transforms: [VideoTransform]

    init(
        aspectRatio: ExportAspectRatio,
        mode: ComparisonMode,
        arrangement: VideoArrangement,
        stackedOpacity: CGFloat? = nil,
        transforms: [VideoTransform]
    ) {
        precondition(transforms.count == 2, "VideoLayoutConfig must have exactly 2 transforms")
        self.aspectRatio = aspectRatio
        self.mode = mode
        self.arrangement = arrangement
        self.stackedOpacity = stackedOpacity
        self.transforms = transforms
    }

    /// The canvas split for a render size of this layout's aspect ratio.
    func canvasLayout(renderSize: CGSize) -> ExportCanvasLayout {
        ExportCanvasLayout(canvas: renderSize, arrangement: arrangement)
    }

    /// How the compositor layers the two cells: blended in stacked mode, one at a time in
    /// sequential, apart otherwise.
    var compositorLayout: CompositorLayout {
        switch mode {
        case .sideBySide, .topBottom: return .sideBySide
        case .sequential:             return .sequential
        case .stacked:                return .stacked(opacity: stackedOpacity ?? 0.5)
        }
    }
}
