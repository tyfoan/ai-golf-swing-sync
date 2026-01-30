//
//  VideoSyncEngine.swift
//  golf-sync-swing
//
//  Calculates sync offset between two videos based on detected impact times
//

import Foundation

/// Result of sync calculation
struct SyncResult {
    let offset: TimeInterval
    let confidence: Double
    let description: String

    var isHighConfidence: Bool {
        confidence >= 0.7
    }
}

/// Service for calculating video sync offsets
final class VideoSyncEngine {

    private let swingDetector = SwingDetector()

    /// Calculate sync offset between two videos
    /// - Parameters:
    ///   - video1: First video (will be used as reference)
    ///   - video2: Second video (offset will be applied to this)
    ///   - progress: Progress callback
    /// - Returns: Sync result with offset and confidence
    func calculateSyncOffset(
        video1: SwingVideo,
        video2: SwingVideo,
        progress: @escaping (Float, String) -> Void
    ) async throws -> SyncResult {
        // Get or detect impact time for video 1
        progress(0.0, "Analyzing first video...")
        let impact1 = try await getImpactTime(for: video1, progress: { p in
            progress(p * 0.45, "Analyzing first video...")
        })

        // Get or detect impact time for video 2
        progress(0.45, "Analyzing second video...")
        let impact2 = try await getImpactTime(for: video2, progress: { p in
            progress(0.45 + p * 0.45, "Analyzing second video...")
        })

        progress(0.9, "Calculating sync...")

        // Calculate offset
        guard let time1 = impact1.time, let time2 = impact2.time else {
            throw SyncEngineError.impactNotDetected
        }

        // Offset = how much to shift video2 relative to video1
        // Positive offset means video2 starts later
        let offset = time1 - time2

        // Combined confidence
        let confidence = (impact1.confidence + impact2.confidence) / 2

        progress(1.0, "Sync complete")

        let description: String
        if confidence >= 0.8 {
            description = "High confidence sync at ball impact"
        } else if confidence >= 0.5 {
            description = "Medium confidence sync - verify manually"
        } else {
            description = "Low confidence - manual adjustment recommended"
        }

        return SyncResult(
            offset: offset,
            confidence: confidence,
            description: description
        )
    }

    /// Get impact time for a video, using cached detection or running new analysis
    private func getImpactTime(
        for video: SwingVideo,
        progress: @escaping (Float) -> Void
    ) async throws -> (time: TimeInterval?, confidence: Double) {
        // Check if we already have an auto-detected swing
        if let existingSwing = video.swings.first(where: { $0.isAutoDetected }) {
            progress(1.0)
            return (existingSwing.contactTime, existingSwing.detectionConfidence)
        }

        // Run detection
        let result = try await swingDetector.analyzeVideo(at: video.localURL, progress: progress)

        return (result.impactTime, result.impactConfidence)
    }

    /// Analyze a video and create auto-detected swing marker if successful
    func analyzeAndMarkSwing(
        for video: SwingVideo,
        progress: @escaping (Float) -> Void
    ) async throws -> SwingDetectionResult {
        let result = try await swingDetector.analyzeVideo(at: video.localURL, progress: progress)

        // Mark video as analyzed
        video.hasBeenAnalyzed = true
        video.analysisDate = Date()

        return result
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
