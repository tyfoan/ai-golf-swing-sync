//
//  SyncTypes.swift
//  golf-sync-swing
//
//  Types used by the video sync system: detection results,
//  sync results, and supporting data structures.
//

import Foundation

// MARK: - Swing Detection Result

struct SwingDetectionResult {
    let impactTime: TimeInterval?
    let impactConfidence: Double
    let topOfBackswingTime: TimeInterval?
    let topOfBackswingConfidence: Double
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    let phases: [SwingPhase]
    let velocityProfile: [VelocityPoint]

    var hasValidDetection: Bool {
        impactTime != nil && impactConfidence > 0.3
    }

    var backswingToImpactDuration: TimeInterval? {
        guard let top = topOfBackswingTime, let impact = impactTime else { return nil }
        let duration = impact - top
        return duration > 0 ? duration : nil
    }
}

struct SwingPhase {
    let name: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
}

struct VelocityPoint {
    let timestamp: TimeInterval
    let velocity: Double
}

// MARK: - Sync Types

enum SyncPointType: String {
    case impact = "Impact"
    case topOfBackswing = "Top of Backswing"
    case swingStart = "Swing Start"
}

struct SyncResult {
    let offset: TimeInterval
    let confidence: Double
    let description: String
    let primarySyncPoint: SyncPointType
    let secondaryOffset: TimeInterval?
    let tempoMatch: Double?
    let video2PlaybackSpeed: Float
    let video1DownswingDuration: TimeInterval?
    let video2DownswingDuration: TimeInterval?

    var isHighConfidence: Bool { confidence >= 0.7 }

    var hasTempoAdjustment: Bool { abs(video2PlaybackSpeed - 1.0) > 0.05 }

    var adjustmentHint: String? {
        guard confidence < 0.6 else { return nil }
        if let secondary = secondaryOffset {
            let drift = abs(secondary - offset)
            if drift > 0.1 {
                return "Swing tempos differ by \(String(format: "%.0f", drift * 1000))ms - consider manual fine-tuning"
            }
        }
        return "Low confidence detection - verify sync visually"
    }

    var tempoDescription: String? {
        guard hasTempoAdjustment else { return nil }
        let percent = Int(abs(video2PlaybackSpeed - 1.0) * 100)
        return video2PlaybackSpeed > 1.0
            ? "Video 2 sped up \(percent)% to match tempo"
            : "Video 2 slowed \(percent)% to match tempo"
    }

    init(
        offset: TimeInterval,
        confidence: Double,
        description: String,
        primarySyncPoint: SyncPointType,
        secondaryOffset: TimeInterval?,
        tempoMatch: Double?,
        video2PlaybackSpeed: Float = 1.0,
        video1DownswingDuration: TimeInterval? = nil,
        video2DownswingDuration: TimeInterval? = nil
    ) {
        self.offset = offset
        self.confidence = confidence
        self.description = description
        self.primarySyncPoint = primarySyncPoint
        self.secondaryOffset = secondaryOffset
        self.tempoMatch = tempoMatch
        self.video2PlaybackSpeed = video2PlaybackSpeed
        self.video1DownswingDuration = video1DownswingDuration
        self.video2DownswingDuration = video2DownswingDuration
    }
}

// MARK: - Errors

enum SyncEngineError: LocalizedError {
    case impactNotDetected
    case analysisFailure(String)

    var errorDescription: String? {
        switch self {
        case .impactNotDetected:
            return "Could not detect ball impact in one or both videos"
        case .analysisFailure(let message):
            return "Sync analysis failed: \(message)"
        }
    }
}
