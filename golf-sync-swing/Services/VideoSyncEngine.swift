//
//  VideoSyncEngine.swift
//  golf-sync-swing
//
//  Orchestrator for golf swing video analysis.
//  Uses ActionClassifierDetector for swing detection.
//  Comparison sync uses contact times from detected SwingMarkers directly.
//

import AVFoundation
import Foundation
import os

final class VideoSyncEngine {

    private let frameIterator = VideoFrameIterator()
    private let offlineTargetFPS: Double = 30

    // MARK: - Multi-Swing Analysis

    func analyzeAllSwings(
        for video: SwingVideo,
        progress: @escaping (Float) -> Void
    ) async throws -> [SwingDetectionResult] {
        AppLogger.sync.info("AUTO-DETECT: video=\(video.localURL.lastPathComponent)")

        let results = try await analyzeAllSwingsWithDetector(
            ActionClassifierDetector(), at: video.localURL, progress: progress
        )

        video.hasBeenAnalyzed = true
        video.analysisDate = Date()
        logResults(results)
        return results
    }

    // MARK: - Private

    private func analyzeAllSwingsWithDetector(
        _ detector: ActionClassifierDetector,
        at url: URL,
        progress: @escaping (Float) -> Void
    ) async throws -> [SwingDetectionResult] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        var detectedSwings: [SwingBounds] = []

        detector.onSwingDetected = { bounds in detectedSwings.append(bounds) }

        try await frameIterator.forEachFrame(
            at: url, timeRangeSeconds: nil, targetFPS: offlineTargetFPS,
            progress: progress
        ) { pixelBuffer, timestamp in
            detector.processFrame(pixelBuffer, at: timestamp)
            return false
        }

        return detectedSwings.map { swing in
            SwingDetectionResult(
                impactTime: swing.impactTime, impactConfidence: swing.confidence,
                startTime: max(0, swing.startTime), endTime: min(duration, swing.endTime)
            )
        }
    }

    private func logResults(_ results: [SwingDetectionResult]) {
        guard !results.isEmpty else {
            AppLogger.sync.info("AUTO-DETECT: no swings detected")
            return
        }
        AppLogger.sync.info("AUTO-DETECT: found \(results.count) swing(s)")
        for (i, result) in results.enumerated() {
            guard let impact = result.impactTime else { continue }
            AppLogger.sync.info("   swing \(i + 1): impact=\(String(format: "%.2f", impact))s conf=\(Int(result.impactConfidence * 100))%")
        }
    }
}
