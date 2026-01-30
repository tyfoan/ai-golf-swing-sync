//
//  SwingVideo.swift
//  golf-sync-swing
//

import Foundation
import SwiftData

@Model
final class SwingVideo {
    var id: UUID = UUID()
    var localURLString: String
    var createdAt: Date = Date()
    var duration: TimeInterval
    var fps: Double
    var thumbnailData: Data?

    @Relationship(deleteRule: .cascade) var swings: [SwingMarker] = []

    var localURL: URL {
        URL(fileURLWithPath: localURLString)
    }

    init(localURL: URL, duration: TimeInterval, fps: Double, thumbnailData: Data? = nil) {
        self.localURLString = localURL.path
        self.duration = duration
        self.fps = fps
        self.thumbnailData = thumbnailData
    }
}
