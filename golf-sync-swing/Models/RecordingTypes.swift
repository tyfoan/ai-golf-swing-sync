//
//  RecordingTypes.swift
//  golf-sync-swing
//
//  Shared types for recording workflow
//

import Foundation

// MARK: - PiP Display Mode

/// What the PiP view is showing during recording
enum PipDisplayMode: Equatable {
    case liveCamera
    case lastSwingReplay
}

// MARK: - Swing Clip

/// Detected swing clip during recording (before saving to SwiftData)
struct SwingClip: Identifiable, Equatable {
    let id: UUID
    let startTime: TimeInterval
    let impactTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let detectionTime: TimeInterval
    let audioConfirmed: Bool
    var isFavorite: Bool = false

    init(from bounds: SwingBounds) {
        self.id = bounds.id
        self.startTime = bounds.startTime
        self.impactTime = bounds.impactTime
        self.endTime = bounds.endTime
        self.confidence = bounds.confidence
        self.detectionTime = bounds.detectionTime
        self.audioConfirmed = bounds.audioConfirmed
    }

    init(id: UUID = UUID(), startTime: TimeInterval, impactTime: TimeInterval, endTime: TimeInterval, confidence: Double, detectionTime: TimeInterval, audioConfirmed: Bool = false, isFavorite: Bool = false) {
        self.id = id
        self.startTime = startTime
        self.impactTime = impactTime
        self.endTime = endTime
        self.confidence = confidence
        self.detectionTime = detectionTime
        self.audioConfirmed = audioConfirmed
        self.isFavorite = isFavorite
    }

    /// How long to wait after detection for video to have all frames
    var requiredWaitTime: TimeInterval {
        // Wait until endTime worth of video has been written
        // endTime - detectionTime = time remaining until follow-through completes
        // + 500ms buffer for file write latency
        let timeUntilEnd = endTime - detectionTime
        return max(0.3, timeUntilEnd + 0.5)
    }
}
