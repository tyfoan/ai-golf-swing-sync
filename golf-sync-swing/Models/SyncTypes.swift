//
//  SyncTypes.swift
//  golf-sync-swing
//
//  Types used by the swing detection and sync systems.
//

import Foundation

// MARK: - Swing Time Range

/// Time bounds for a single swing within a video.
struct SwingTimeRange: Hashable {
    let startTime: TimeInterval
    let contactTime: TimeInterval
    let endTime: TimeInterval

    var duration: TimeInterval { endTime - startTime }
}

// MARK: - Swing Detection Result

struct SwingDetectionResult {
    let impactTime: TimeInterval?
    let impactConfidence: Double
    let startTime: TimeInterval?
    let endTime: TimeInterval?

    var hasValidDetection: Bool {
        impactTime != nil && impactConfidence > 0.3
    }
}

// MARK: - Errors

enum SyncEngineError: LocalizedError {
    case analysisFailure(String)

    var errorDescription: String? {
        switch self {
        case .analysisFailure(let message):
            return String(localized: "Analysis failed: \(message)", comment: "SyncEngineError: motion-sync analysis failure — placeholder is the underlying reason")
        }
    }
}
