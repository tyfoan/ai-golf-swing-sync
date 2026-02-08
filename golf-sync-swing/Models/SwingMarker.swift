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

    // User metadata
    var isFavorite: Bool = false

    @Relationship(inverse: \SwingVideo.swings) var video: SwingVideo?

    // MARK: - Init

    init(startTime: TimeInterval, contactTime: TimeInterval, endTime: TimeInterval) {
        // Ensure valid ordering: start < contact < end
        let validStart = max(0, startTime)
        let validContact = max(validStart, contactTime)
        let validEnd = max(validContact, endTime)

        self.startTime = validStart
        self.contactTime = validContact
        self.endTime = validEnd
    }

    /// Create from auto-detection result
    init(from detection: SwingDetectionResult) {
        let start = detection.startTime ?? 0
        let contact = detection.impactTime ?? 0
        let end = detection.endTime ?? 0

        // Ensure valid ordering using local variables (can't reference self before init completes)
        let validStart = max(0, start)
        let validContact = max(validStart, contact)
        let validEnd = max(validContact, end)

        self.startTime = validStart
        self.contactTime = validContact
        self.endTime = validEnd

        self.isAutoDetected = true
        self.detectionConfidence = detection.impactConfidence
    }

    // MARK: - Computed Properties

    var duration: TimeInterval {
        endTime - startTime
    }

    /// Whether the marker times are in valid order
    var isValid: Bool {
        startTime >= 0 && startTime <= contactTime && contactTime <= endTime
    }

    /// Confidence level as a descriptive string
    var confidenceDescription: String {
        switch detectionConfidence {
        case 0.8...: return "High"
        case 0.5..<0.8: return "Medium"
        default: return "Low"
        }
    }

    // MARK: - Validation

    /// Update times with validation to ensure proper ordering
    func updateTimes(start: TimeInterval? = nil, contact: TimeInterval? = nil, end: TimeInterval? = nil) {
        var newStart = start ?? startTime
        var newContact = contact ?? contactTime
        var newEnd = end ?? endTime

        // Ensure valid ordering
        newStart = max(0, newStart)
        newContact = max(newStart, newContact)
        newEnd = max(newContact, newEnd)

        startTime = newStart
        contactTime = newContact
        endTime = newEnd
    }
}
