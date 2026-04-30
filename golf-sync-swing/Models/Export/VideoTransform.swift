//
//  VideoTransform.swift
//  golf-sync-swing
//
//  Per-video transform state owned by the editor and read by the exporter.
//

import CoreGraphics

struct VideoTransform: Equatable {
    var scale: CGFloat = 1.0
    var offset: CGPoint = .zero
    var containerSize: CGSize = .zero
    var isMuted: Bool = false

    static let identity = VideoTransform()
}
