//
//  SwingMarker.swift
//  golf-sync-swing
//

import Foundation
import SwiftData

@Model
final class SwingMarker {
    var id: UUID = UUID()
    var startTime: TimeInterval  // Green - swing start
    var contactTime: TimeInterval  // Orange - ball contact (impact)
    var endTime: TimeInterval  // Green - swing end
    var createdAt: Date = Date()

    // Auto-detection metadata
    var isAutoDetected: Bool = false
    var detectionConfidence: Double = 1.0  // 0.0 to 1.0

    @Relationship(inverse: \SwingVideo.swings) var video: SwingVideo?

    init(startTime: TimeInterval, contactTime: TimeInterval, endTime: TimeInterval) {
        self.startTime = startTime
        self.contactTime = contactTime
        self.endTime = endTime
    }

    /// Create from auto-detection result
    init(from detection: SwingDetectionResult) {
        self.startTime = detection.startTime ?? 0
        self.contactTime = detection.impactTime ?? 0
        self.endTime = detection.endTime ?? 0
        self.isAutoDetected = true
        self.detectionConfidence = detection.impactConfidence
    }

    var duration: TimeInterval {
        endTime - startTime
    }

    /// Confidence level as a descriptive string
    var confidenceDescription: String {
        switch detectionConfidence {
        case 0.8...: return "High"
        case 0.5..<0.8: return "Medium"
        default: return "Low"
        }
    }
}
