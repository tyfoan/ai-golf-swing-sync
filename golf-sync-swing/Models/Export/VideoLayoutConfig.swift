//
//  VideoLayoutConfig.swift
//  golf-sync-swing
//
//  The contract between the export editor and the exporter:
//  output aspect ratio + comparison mode + per-video transforms (always 2).
//

import CoreGraphics
import Foundation

struct VideoLayoutConfig: Equatable {
    let aspectRatio: ExportAspectRatio
    let mode: ComparisonMode
    let stackedOpacity: CGFloat?    // only used when mode == .stacked
    let transforms: [VideoTransform]

    init(
        aspectRatio: ExportAspectRatio,
        mode: ComparisonMode,
        stackedOpacity: CGFloat? = nil,
        transforms: [VideoTransform]
    ) {
        precondition(transforms.count == 2, "VideoLayoutConfig must have exactly 2 transforms")
        self.aspectRatio = aspectRatio
        self.mode = mode
        self.stackedOpacity = stackedOpacity
        self.transforms = transforms
    }

    static func identity(aspectRatio: ExportAspectRatio, mode: ComparisonMode) -> VideoLayoutConfig {
        let v1 = VideoTransform()
        var v2 = VideoTransform()
        v2.isMuted = true
        return VideoLayoutConfig(
            aspectRatio: aspectRatio, mode: mode,
            stackedOpacity: mode == .stacked ? 0.5 : nil,
            transforms: [v1, v2]
        )
    }
}
