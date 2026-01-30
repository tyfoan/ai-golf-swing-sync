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

    // Auto-detection status
    var hasBeenAnalyzed: Bool = false
    var analysisDate: Date?

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

    /// Get the primary detected impact time (first auto-detected swing)
    var detectedImpactTime: TimeInterval? {
        swings.first { $0.isAutoDetected }?.contactTime
    }

    /// Check if video has a high-confidence auto-detected swing
    var hasHighConfidenceDetection: Bool {
        swings.contains { $0.isAutoDetected && $0.detectionConfidence >= 0.7 }
    }
}
