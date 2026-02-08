//
//  VideoSyncEngine.swift
//  golf-sync-swing
//
//  Orchestrator for golf swing video synchronization.
//  Delegates to collaborators:
//    VideoFrameIterator     - Frame extraction from video files
//    TempoAnalyzer          - Swing tempo comparison
//    SyncStrategySelector   - Best sync point selection
//    CrossCorrelationRefiner - Sub-frame alignment refinement
//
//  Types: SyncTypes.swift (SwingDetectionResult, SyncResult, etc.)
//

import AVFoundation
import Foundation

final class VideoSyncEngine {

    private let frameIterator = VideoFrameIterator()
    private let tempoAnalyzer = TempoAnalyzer()
    private let strategySelector = SyncStrategySelector()
    private let correlationRefiner = CrossCorrelationRefiner()
    private let offlineTargetFPS: Double = 30

    // MARK: - Primary Sync API

    func calculateSyncOffset(
        video1: SwingVideo,
        video2: SwingVideo,
        approximateContact1: TimeInterval? = nil,
        approximateContact2: TimeInterval? = nil,
        progress: @escaping (Float, String) -> Void
    ) async throws -> SyncResult {
        progress(0.0, "Analyzing first video...")
        let result1 = try await analyzeVideoFresh(
            video1, nearTime: approximateContact1,
            progress: { p in progress(p * 0.40, "Analyzing first video...") }
        )

        progress(0.40, "Analyzing second video...")
        let result2 = try await analyzeVideoFresh(
            video2, nearTime: approximateContact2,
            progress: { p in progress(0.40 + p * 0.40, "Analyzing second video...") }
        )

        progress(0.80, "Calculating optimal sync...")
        let syncResult = calculateMultiPointSync(result1: result1, result2: result2)

        progress(0.90, "Refining alignment...")
        let refined = correlationRefiner.refine(
            baseResult: syncResult,
            profile1: result1.velocityProfile,
            profile2: result2.velocityProfile
        )

        progress(1.0, "Sync complete")
        return refined
    }

    // MARK: - Multi-Swing Analysis

    func analyzeAllSwings(
        for video: SwingVideo,
        model: AutoDetectModel = .swingNet,
        progress: @escaping (Float) -> Void
    ) async throws -> [SwingDetectionResult] {
        print("🪄 AUTO-DETECT: model=\(model.shortName) video=\(video.localURL.lastPathComponent)")

        let results: [SwingDetectionResult]
        switch model {
        case .actionClassifier:
            results = try await analyzeAllSwingsWithDetector(
                ActionClassifierDetector(), at: video.localURL, progress: progress
            )
        case .swingNet:
            results = try await analyzeAllSwingsWithSwingNet(at: video.localURL, progress: progress)
        }

        video.hasBeenAnalyzed = true
        video.analysisDate = Date()
        logResults(results)
        return results
    }

    // MARK: - Private: Video Analysis

    /// Fresh SwingNet analysis focused on a narrow window around the approximate contact time.
    /// Skips the cache — always runs SwingNet for precise frame-level + interpolated impact detection.
    private func analyzeVideoFresh(
        _ video: SwingVideo,
        nearTime: TimeInterval?,
        progress: @escaping (Float) -> Void
    ) async throws -> SwingDetectionResult {
        let windowRadius: TimeInterval = 3.0
        let timeRange: ClosedRange<TimeInterval>? = nearTime.map { t in
            max(0, t - windowRadius)...(t + windowRadius)
        }
        return try await analyzeWithSwingNet(
            at: video.localURL, timeRange: timeRange, progress: progress
        )
    }

    /// Cached analysis for library auto-detection (ActionClassifier times acceptable)
    private func analyzeVideoCached(
        _ video: SwingVideo,
        progress: @escaping (Float) -> Void
    ) async throws -> SwingDetectionResult {
        if let cached = video.swings.first(where: { $0.isAutoDetected }) {
            progress(1.0)
            return SwingDetectionResult(
                impactTime: cached.contactTime,
                impactConfidence: cached.detectionConfidence,
                topOfBackswingTime: nil, topOfBackswingConfidence: 0,
                startTime: cached.startTime, endTime: cached.endTime,
                phases: [], velocityProfile: []
            )
        }
        return try await analyzeWithSwingNet(at: video.localURL, progress: progress)
    }

    private func analyzeWithSwingNet(
        at url: URL,
        timeRange: ClosedRange<TimeInterval>? = nil,
        progress: @escaping (Float) -> Void
    ) async throws -> SwingDetectionResult {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds

        let detector = SwingNetDetector()
        var detected: SwingBounds?
        var framesProcessed = 0
        detector.onSwingDetected = { bounds in detected = bounds }

        try await frameIterator.forEachFrame(
            at: url, timeRangeSeconds: timeRange, targetFPS: offlineTargetFPS,
            progress: progress
        ) { pixelBuffer, timestamp in
            framesProcessed += 1
            detector.processFrame(pixelBuffer, at: timestamp)
            return detected != nil
        }

        guard let swing = detected else {
            return emptyResult()
        }

        return SwingDetectionResult(
            impactTime: swing.impactTime,
            impactConfidence: swing.confidence,
            topOfBackswingTime: detector.topOfBackswingTime,
            topOfBackswingConfidence: detector.topOfBackswingConfidence,
            startTime: max(0, swing.startTime),
            endTime: min(duration, swing.endTime),
            phases: [], velocityProfile: []
        )
    }

    // MARK: - Private: Multi-Swing Helpers

    private func analyzeAllSwingsWithDetector(
        _ detector: ActionClassifierDetector,
        at url: URL,
        progress: @escaping (Float) -> Void
    ) async throws -> [SwingDetectionResult] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        var detectedSwings: [SwingBounds] = []
        var framesProcessed = 0

        detector.onSwingDetected = { bounds in detectedSwings.append(bounds) }

        try await frameIterator.forEachFrame(
            at: url, timeRangeSeconds: nil, targetFPS: offlineTargetFPS,
            progress: progress
        ) { pixelBuffer, timestamp in
            framesProcessed += 1
            detector.processFrame(pixelBuffer, at: timestamp)
            return false
        }

        return detectedSwings.map { swing in
            SwingDetectionResult(
                impactTime: swing.impactTime, impactConfidence: swing.confidence,
                topOfBackswingTime: nil, topOfBackswingConfidence: 0,
                startTime: max(0, swing.startTime), endTime: min(duration, swing.endTime),
                phases: [], velocityProfile: []
            )
        }
    }

    private func analyzeAllSwingsWithSwingNet(
        at url: URL, progress: @escaping (Float) -> Void
    ) async throws -> [SwingDetectionResult] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let detector = SwingNetDetector()
        var framesProcessed = 0

        try await frameIterator.forEachFrame(
            at: url, timeRangeSeconds: nil, targetFPS: offlineTargetFPS,
            progress: progress
        ) { pixelBuffer, timestamp in
            framesProcessed += 1
            detector.processFrame(pixelBuffer, at: timestamp)
            return false
        }

        return detector.detectedSwings.map { swing in
            SwingDetectionResult(
                impactTime: swing.impactTime, impactConfidence: swing.confidence,
                topOfBackswingTime: nil, topOfBackswingConfidence: 0,
                startTime: max(0, swing.startTime), endTime: min(duration, swing.endTime),
                phases: [], velocityProfile: []
            )
        }
    }

    // MARK: - Private: Sync Calculation

    private func calculateMultiPointSync(
        result1: SwingDetectionResult,
        result2: SwingDetectionResult
    ) -> SyncResult {
        let impactOffset = calculateOffset(
            time1: result1.impactTime, confidence1: result1.impactConfidence,
            time2: result2.impactTime, confidence2: result2.impactConfidence
        )
        let backswingOffset = calculateOffset(
            time1: result1.topOfBackswingTime, confidence1: result1.topOfBackswingConfidence,
            time2: result2.topOfBackswingTime, confidence2: result2.topOfBackswingConfidence
        )
        let tempo = tempoAnalyzer.analyze(result1: result1, result2: result2)

        return strategySelector.selectBestSync(
            impactOffset: impactOffset, backswingOffset: backswingOffset, tempo: tempo
        )
    }

    private func calculateOffset(
        time1: TimeInterval?, confidence1: Double,
        time2: TimeInterval?, confidence2: Double
    ) -> (offset: TimeInterval?, confidence: Double) {
        guard let t1 = time1, let t2 = time2 else { return (nil, 0) }
        return (t1 - t2, (confidence1 + confidence2) / 2)
    }

    // MARK: - Private: Utilities

    private func emptyResult() -> SwingDetectionResult {
        SwingDetectionResult(
            impactTime: nil, impactConfidence: 0,
            topOfBackswingTime: nil, topOfBackswingConfidence: 0,
            startTime: nil, endTime: nil,
            phases: [], velocityProfile: []
        )
    }

    private func logResults(_ results: [SwingDetectionResult]) {
        if results.isEmpty {
            print("🪄 AUTO-DETECT: no swings detected")
        } else {
            print("🪄 AUTO-DETECT: found \(results.count) swing(s)")
            for (i, result) in results.enumerated() {
                if let impact = result.impactTime {
                    print("   swing \(i + 1): impact=\(String(format: "%.2f", impact))s conf=\(Int(result.impactConfidence * 100))%")
                }
            }
        }
    }
}
