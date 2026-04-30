//
//  VideoLayoutConfig.swift
//  golf-sync-swing
//
//  The contract between the export editor and the exporter:
//  output aspect ratio + per-video transforms (always 2 entries in this app).
//

import Foundation

struct VideoLayoutConfig: Equatable {
    let aspectRatio: ExportAspectRatio
    let transforms: [VideoTransform]

    init(aspectRatio: ExportAspectRatio, transforms: [VideoTransform]) {
        precondition(transforms.count == 2, "VideoLayoutConfig must have exactly 2 transforms")
        self.aspectRatio = aspectRatio
        self.transforms = transforms
    }

    static func identity(aspectRatio: ExportAspectRatio) -> VideoLayoutConfig {
        var v1 = VideoTransform()
        var v2 = VideoTransform()
        v2.isMuted = true
        return VideoLayoutConfig(aspectRatio: aspectRatio, transforms: [v1, v2])
    }
}
