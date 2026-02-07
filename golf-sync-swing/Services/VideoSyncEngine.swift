//
//  VideoSyncEngine.swift
//  golf-sync-swing
//
//  Advanced multi-point synchronization engine for golf swing videos.
//  Uses impact as primary sync point with top-of-backswing as secondary.
//  Implements cross-correlation for sub-frame alignment accuracy.
//

import Foundation
import AVFoundation
import Accelerate

// MARK: - Swing Detection Result

/// Result of swing detection analysis
struct SwingDetectionResult {
    let impactTime: TimeInterval?
    let impactConfidence: Double
    let topOfBackswingTime: TimeInterval?
    let topOfBackswingConfidence: Double
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    let phases: [SwingPhase]
    let velocityProfile: [VelocityPoint]

    /// Whether detection found a valid swing
    var hasValidDetection: Bool {
        impactTime != nil && impactConfidence > 0.3
    }

    /// Duration from top of backswing to impact (for tempo analysis)
    var backswingToImpactDuration: TimeInterval? {
        guard let top = topOfBackswingTime, let impact = impactTime else { return nil }
        let duration = impact - top
        return duration > 0 ? duration : nil
    }
}

/// A phase of the golf swing
struct SwingPhase {
    let name: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
}

/// Velocity data point for cross-correlation
struct VelocityPoint {
    let timestamp: TimeInterval
    let velocity: Double
}

// MARK: - Sync Types

/// Sync point types for multi-point alignment
enum SyncPointType: String {
    case impact = "Impact"
    case topOfBackswing = "Top of Backswing"
    case swingStart = "Swing Start"
}

/// Result of sync calculation with detailed diagnostics
struct SyncResult {
    let offset: TimeInterval
    let confidence: Double
    let description: String
    let primarySyncPoint: SyncPointType
    let secondaryOffset: TimeInterval?  // Offset at secondary sync point (for validation)
    let tempoMatch: Double?  // How similar the swing tempos are (0-1)

    /// Playback speed adjustment for video2 to match video1's tempo (1.0 = no change)
    let video2PlaybackSpeed: Float

    /// Duration of downswing phase for each video (for tempo display)
    let video1DownswingDuration: TimeInterval?
    let video2DownswingDuration: TimeInterval?

    var isHighConfidence: Bool {
        confidence >= 0.7
    }

    /// Whether tempo adjustment is recommended
    var hasTempoAdjustment: Bool {
        abs(video2PlaybackSpeed - 1.0) > 0.05
    }

    /// Recommended manual adjustment direction if low confidence
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

    /// Description of tempo adjustment
    var tempoDescription: String? {
        guard hasTempoAdjustment else { return nil }
        let percent = Int(abs(video2PlaybackSpeed - 1.0) * 100)
        if video2PlaybackSpeed > 1.0 {
            return "Video 2 sped up \(percent)% to match tempo"
        } else {
            return "Video 2 slowed \(percent)% to match tempo"
        }
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

/// Service for calculating video sync offsets using SwingNet
final class VideoSyncEngine {

    // MARK: - Primary Sync API

    /// Calculate sync offset between two videos using multi-point alignment
    /// - Parameters:
    ///   - video1: First video (reference)
    ///   - video2: Second video (offset applied to this)
    ///   - progress: Progress callback
    /// - Returns: Sync result with offset and confidence
    func calculateSyncOffset(
        video1: SwingVideo,
        video2: SwingVideo,
        progress: @escaping (Float, String) -> Void
    ) async throws -> SyncResult {
        // Analyze video 1
        progress(0.0, "Analyzing first video...")
        let result1 = try await analyzeVideo(video1, progress: { p in
            progress(p * 0.40, "Analyzing first video...")
        })

        // Analyze video 2
        progress(0.40, "Analyzing second video...")
        let result2 = try await analyzeVideo(video2, progress: { p in
            progress(0.40 + p * 0.40, "Analyzing second video...")
        })

        progress(0.80, "Calculating optimal sync...")

        // Calculate multi-point sync
        let syncResult = calculateMultiPointSync(result1: result1, result2: result2)

        progress(0.90, "Refining alignment...")

        // If we have velocity profiles, try cross-correlation for fine-tuning
        let refinedResult = refineWithCrossCorrelation(
            baseResult: syncResult,
            profile1: result1.velocityProfile,
            profile2: result2.velocityProfile
        )

        progress(1.0, "Sync complete")

        return refinedResult
    }

    // MARK: - Video Analysis

    private func analyzeVideo(
        _ video: SwingVideo,
        progress: @escaping (Float) -> Void
    ) async throws -> SwingDetectionResult {
        // Check for cached detection
        if let existingSwing = video.swings.first(where: { $0.isAutoDetected }) {
            progress(1.0)
            // Create a minimal result from cached data
            return SwingDetectionResult(
                impactTime: existingSwing.contactTime,
                impactConfidence: existingSwing.detectionConfidence,
                topOfBackswingTime: nil,  // Not cached
                topOfBackswingConfidence: 0,
                startTime: existingSwing.startTime,
                endTime: existingSwing.endTime,
                phases: [],
                velocityProfile: []
            )
        }

        // Run SwingNet analysis
        return try await analyzeWithSwingNet(at: video.localURL, progress: progress)
    }

    // MARK: - Multi-Point Sync Calculation

    private func calculateMultiPointSync(
        result1: SwingDetectionResult,
        result2: SwingDetectionResult
    ) -> SyncResult {
        // Primary: Impact-based sync
        let impactOffset = calculateImpactOffset(result1: result1, result2: result2)

        // Secondary: Top-of-backswing sync (for validation)
        let backswingOffset = calculateBackswingOffset(result1: result1, result2: result2)

        // Tempo comparison and speed adjustment calculation
        let tempo = calculateTempoMatch(result1: result1, result2: result2)

        // Determine best sync strategy
        return selectBestSync(
            impactOffset: impactOffset,
            backswingOffset: backswingOffset,
            tempo: tempo
        )
    }

    private func calculateImpactOffset(
        result1: SwingDetectionResult,
        result2: SwingDetectionResult
    ) -> (offset: TimeInterval?, confidence: Double) {
        guard let impact1 = result1.impactTime,
              let impact2 = result2.impactTime else {
            return (nil, 0)
        }

        let offset = impact1 - impact2
        let confidence = (result1.impactConfidence + result2.impactConfidence) / 2

        return (offset, confidence)
    }

    private func calculateBackswingOffset(
        result1: SwingDetectionResult,
        result2: SwingDetectionResult
    ) -> (offset: TimeInterval?, confidence: Double) {
        guard let top1 = result1.topOfBackswingTime,
              let top2 = result2.topOfBackswingTime else {
            return (nil, 0)
        }

        let offset = top1 - top2
        let confidence = (result1.topOfBackswingConfidence + result2.topOfBackswingConfidence) / 2

        return (offset, confidence)
    }

    /// Tempo analysis result
    private struct TempoAnalysis {
        let match: Double  // 0-1, how similar tempos are
        let speedAdjustment: Float  // Playback speed for video2 to match video1
        let duration1: TimeInterval?
        let duration2: TimeInterval?
    }

    private func calculateTempoMatch(
        result1: SwingDetectionResult,
        result2: SwingDetectionResult
    ) -> TempoAnalysis {
        guard let duration1 = result1.backswingToImpactDuration,
              let duration2 = result2.backswingToImpactDuration,
              duration1 > 0.1, duration2 > 0.1 else {
            return TempoAnalysis(match: 1.0, speedAdjustment: 1.0, duration1: nil, duration2: nil)
        }

        // Tempo match: how similar are the backswing-to-impact durations
        // Perfect match = 1.0, very different = closer to 0
        let match = min(duration1, duration2) / max(duration1, duration2)

        // Speed adjustment: make video2 play at video1's tempo
        // If video2 swing is slower (longer duration), speed it up
        // If video2 swing is faster (shorter duration), slow it down
        var speedRatio = Float(duration2 / duration1)

        // Clamp to reasonable range (±30%)
        speedRatio = max(0.7, min(1.3, speedRatio))

        // Only adjust if difference is meaningful (>8%)
        if abs(speedRatio - 1.0) < 0.08 {
            speedRatio = 1.0
        }

        return TempoAnalysis(
            match: match,
            speedAdjustment: speedRatio,
            duration1: duration1,
            duration2: duration2
        )
    }

    private func selectBestSync(
        impactOffset: (offset: TimeInterval?, confidence: Double),
        backswingOffset: (offset: TimeInterval?, confidence: Double),
        tempo: TempoAnalysis
    ) -> SyncResult {
        // Case 1: Both sync points available and agree
        if let impact = impactOffset.offset,
           let backswing = backswingOffset.offset {
            let offsetDiff = abs(impact - backswing)

            if offsetDiff < 0.15 {
                // Great agreement - high confidence
                let combinedConfidence = min(1.0, (impactOffset.confidence + backswingOffset.confidence) / 2 + 0.1)
                return SyncResult(
                    offset: impact,
                    confidence: combinedConfidence,
                    description: "High confidence sync - impact and backswing aligned",
                    primarySyncPoint: .impact,
                    secondaryOffset: backswing,
                    tempoMatch: tempo.match,
                    video2PlaybackSpeed: tempo.speedAdjustment,
                    video1DownswingDuration: tempo.duration1,
                    video2DownswingDuration: tempo.duration2
                )
            } else if offsetDiff < 0.3 {
                // Moderate agreement - use weighted average
                let weightedOffset = (impact * impactOffset.confidence + backswing * backswingOffset.confidence)
                    / (impactOffset.confidence + backswingOffset.confidence)
                let combinedConfidence = (impactOffset.confidence + backswingOffset.confidence) / 2 * 0.85
                return SyncResult(
                    offset: weightedOffset,
                    confidence: combinedConfidence,
                    description: "Medium confidence - slight tempo difference between swings",
                    primarySyncPoint: .impact,
                    secondaryOffset: backswing,
                    tempoMatch: tempo.match,
                    video2PlaybackSpeed: tempo.speedAdjustment,
                    video1DownswingDuration: tempo.duration1,
                    video2DownswingDuration: tempo.duration2
                )
            } else {
                // Significant disagreement - different swing tempos
                // Tempo adjustment becomes more important here
                return SyncResult(
                    offset: impact,
                    confidence: impactOffset.confidence * 0.7,
                    description: "Different tempos - synced at impact with speed adjustment",
                    primarySyncPoint: .impact,
                    secondaryOffset: backswing,
                    tempoMatch: tempo.match,
                    video2PlaybackSpeed: tempo.speedAdjustment,
                    video1DownswingDuration: tempo.duration1,
                    video2DownswingDuration: tempo.duration2
                )
            }
        }

        // Case 2: Only impact available
        if let impact = impactOffset.offset {
            return SyncResult(
                offset: impact,
                confidence: impactOffset.confidence,
                description: impactOffset.confidence >= 0.7
                    ? "Synced at ball impact"
                    : "Synced at impact (medium confidence)",
                primarySyncPoint: .impact,
                secondaryOffset: nil,
                tempoMatch: tempo.match,
                video2PlaybackSpeed: tempo.speedAdjustment,
                video1DownswingDuration: tempo.duration1,
                video2DownswingDuration: tempo.duration2
            )
        }

        // Case 3: Only backswing available (unusual)
        if let backswing = backswingOffset.offset {
            return SyncResult(
                offset: backswing,
                confidence: backswingOffset.confidence * 0.8,
                description: "Synced at top of backswing (no impact detected)",
                primarySyncPoint: .topOfBackswing,
                secondaryOffset: nil,
                tempoMatch: tempo.match,
                video2PlaybackSpeed: tempo.speedAdjustment,
                video1DownswingDuration: tempo.duration1,
                video2DownswingDuration: tempo.duration2
            )
        }

        // Case 4: Nothing detected
        return SyncResult(
            offset: 0,
            confidence: 0,
            description: "Could not detect sync points - manual alignment required",
            primarySyncPoint: .impact,
            secondaryOffset: nil,
            tempoMatch: nil,
            video2PlaybackSpeed: 1.0,
            video1DownswingDuration: nil,
            video2DownswingDuration: nil
        )
    }

    // MARK: - Cross-Correlation Refinement

    /// Refine sync offset using velocity profile cross-correlation
    private func refineWithCrossCorrelation(
        baseResult: SyncResult,
        profile1: [VelocityPoint],
        profile2: [VelocityPoint]
    ) -> SyncResult {
        // Need sufficient data for cross-correlation
        guard profile1.count >= 20, profile2.count >= 20 else {
            return baseResult
        }

        // Extract velocity arrays around the sync region
        guard let impact1 = profile1.first(where: { abs($0.timestamp - (profile1.last?.timestamp ?? 0) * 0.6) < 0.5 }),
              let impact2 = profile2.first(where: { abs($0.timestamp - (profile2.last?.timestamp ?? 0) * 0.6) < 0.5 }) else {
            return baseResult
        }

        // Get 1-second window around estimated impact for cross-correlation
        let window1 = profile1.filter {
            $0.timestamp >= impact1.timestamp - 0.5 && $0.timestamp <= impact1.timestamp + 0.5
        }
        let window2 = profile2.filter {
            $0.timestamp >= impact2.timestamp - 0.5 && $0.timestamp <= impact2.timestamp + 0.5
        }

        guard window1.count >= 10, window2.count >= 10 else {
            return baseResult
        }

        // Normalize velocity arrays
        let velocities1 = normalizeArray(window1.map { $0.velocity })
        let velocities2 = normalizeArray(window2.map { $0.velocity })

        // Calculate cross-correlation to find optimal sub-frame alignment
        let correlation = crossCorrelation(signal1: velocities1, signal2: velocities2)

        // Find peak correlation
        guard let peakIndex = correlation.enumerated().max(by: { $0.element < $1.element })?.offset else {
            return baseResult
        }

        // Convert peak index to time offset adjustment
        let centerIndex = correlation.count / 2
        let frameOffset = peakIndex - centerIndex
        let avgFrameDuration = (window1.last!.timestamp - window1.first!.timestamp) / Double(window1.count - 1)
        let refinementOffset = Double(frameOffset) * avgFrameDuration

        // Only apply refinement if it's small (< 100ms) and correlation is strong
        let peakCorrelation = correlation[peakIndex]
        guard abs(refinementOffset) < 0.1 && peakCorrelation > 0.7 else {
            return baseResult
        }

        // Apply refinement
        let refinedOffset = baseResult.offset + refinementOffset
        let refinedConfidence = min(1.0, baseResult.confidence + (peakCorrelation - 0.7) * 0.2)

        return SyncResult(
            offset: refinedOffset,
            confidence: refinedConfidence,
            description: baseResult.description + " (cross-correlation refined)",
            primarySyncPoint: baseResult.primarySyncPoint,
            secondaryOffset: baseResult.secondaryOffset,
            tempoMatch: baseResult.tempoMatch,
            video2PlaybackSpeed: baseResult.video2PlaybackSpeed,
            video1DownswingDuration: baseResult.video1DownswingDuration,
            video2DownswingDuration: baseResult.video2DownswingDuration
        )
    }

    /// Normalize array to zero mean and unit variance
    private func normalizeArray(_ array: [Double]) -> [Double] {
        guard !array.isEmpty else { return array }

        let mean = array.reduce(0, +) / Double(array.count)
        let variance = array.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(array.count)
        let stdDev = sqrt(variance)

        guard stdDev > 0.001 else { return array.map { _ in 0 } }

        return array.map { ($0 - mean) / stdDev }
    }

    /// Calculate normalized cross-correlation between two signals
    private func crossCorrelation(signal1: [Double], signal2: [Double]) -> [Double] {
        let n1 = signal1.count
        let n2 = signal2.count
        let resultLength = n1 + n2 - 1

        var result = [Double](repeating: 0, count: resultLength)

        for lag in 0..<resultLength {
            var sum: Double = 0
            var count: Double = 0

            for i in 0..<n1 {
                let j = i + lag - n1 + 1
                if j >= 0 && j < n2 {
                    sum += signal1[i] * signal2[j]
                    count += 1
                }
            }

            result[lag] = count > 0 ? sum / count : 0
        }

        return result
    }

    // MARK: - Convenience Methods

    private let offlineTargetFPS: Double = 30

    private func forEachVideoFrame(
        at url: URL,
        timeRangeSeconds: ClosedRange<TimeInterval>?,
        targetFPS: Double,
        progress: @escaping (Float) -> Void,
        process: (CVPixelBuffer, TimeInterval) -> Bool
    ) async throws {
        let asset = AVURLAsset(url: url)
        let durationSeconds = try await asset.load(.duration).seconds
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw SyncEngineError.analysisFailure("No video track")
        }

        let reader = try AVAssetReader(asset: asset)

        let clampedRange: ClosedRange<TimeInterval>? = timeRangeSeconds.flatMap { range in
            let start = max(0, range.lowerBound)
            let end = min(durationSeconds, range.upperBound)
            guard end > start else { return nil }
            return start...end
        }

        if let range = clampedRange {
            let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
            let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
            let duration = CMTimeSubtract(end, start)
            reader.timeRange = CMTimeRange(start: start, duration: duration)
        }

        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]

        // Use a video composition output so frames are oriented using the track's preferred transform.
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: settings)
        output.videoComposition = AVMutableVideoComposition(propertiesOf: asset)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? SyncEngineError.analysisFailure("Failed to start video reader")
        }

        let progressStart = clampedRange?.lowerBound ?? 0
        let progressEnd = clampedRange?.upperBound ?? durationSeconds
        let progressSpan = max(0.001, progressEnd - progressStart)
        let minFrameInterval = 1.0 / max(1.0, targetFPS)

        var lastProcessedTimestamp = -Double.greatestFiniteMagnitude

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

            // Downsample to ~targetFPS (important for ML window sizes trained at 30fps).
            if timestamp - lastProcessedTimestamp < minFrameInterval {
                continue
            }
            lastProcessedTimestamp = timestamp

            let clampedTime = max(progressStart, min(progressEnd, timestamp))
            progress(Float((clampedTime - progressStart) / progressSpan))

            let shouldStop = process(pixelBuffer, timestamp)
            if shouldStop {
                reader.cancelReading()
                break
            }
        }

        if reader.status == .failed {
            throw reader.error ?? SyncEngineError.analysisFailure("Video reader failed")
        }

        progress(1.0)
    }

    private func analyzeWithSwingNet(at url: URL, progress: @escaping (Float) -> Void) async throws -> SwingDetectionResult {
        progress(0.0)

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        print("📹 SwingNet analysis: video duration=\(String(format: "%.2f", duration))s")
        print("📹 SwingNet: scanning FULL video (0 - \(String(format: "%.2f", duration))s)")

        let detector = SwingNetDetector()
        var detected: SwingBounds?
        var framesProcessed = 0
        detector.onSwingDetected = { bounds in
            detected = bounds
        }

        try await forEachVideoFrame(
            at: url,
            timeRangeSeconds: nil,  // Scan entire video
            targetFPS: offlineTargetFPS,
            progress: progress,
            process: { pixelBuffer, timestamp in
                framesProcessed += 1
                detector.processFrame(pixelBuffer, at: timestamp)
                return detected != nil
            }
        )

        print("📹 SwingNet: Processed \(framesProcessed) total frames")

        guard let swing = detected else {
            print("⚠️ SwingNet: No swing detected after \(framesProcessed) frames")
            return SwingDetectionResult(
                impactTime: nil,
                impactConfidence: 0,
                topOfBackswingTime: nil,
                topOfBackswingConfidence: 0,
                startTime: nil,
                endTime: nil,
                phases: [],
                velocityProfile: []
            )
        }

        print("✅ SwingNet: Detected swing at impact=\(String(format: "%.2f", swing.impactTime))s")
        return SwingDetectionResult(
            impactTime: swing.impactTime,
            impactConfidence: swing.confidence,
            topOfBackswingTime: detector.topOfBackswingTime,
            topOfBackswingConfidence: detector.topOfBackswingConfidence,
            startTime: max(0, swing.startTime),
            endTime: min(duration, swing.endTime),
            phases: [],
            velocityProfile: []
        )
    }

    /// Analyze a video and return all detected swings
    func analyzeAllSwings(
        for video: SwingVideo,
        model: AutoDetectModel = .swingNet,
        progress: @escaping (Float) -> Void
    ) async throws -> [SwingDetectionResult] {
        print("🪄 AUTO-DETECT: model=\(model.shortName) video=\(video.localURL.lastPathComponent)")

        let results: [SwingDetectionResult]
        switch model {
        case .actionClassifier:
            results = try await analyzeAllSwingsWithActionClassifier(at: video.localURL, progress: progress)
        case .swingNet:
            results = try await analyzeAllSwingsWithSwingNet(at: video.localURL, progress: progress)
        }

        video.hasBeenAnalyzed = true
        video.analysisDate = Date()

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

        return results
    }

    // MARK: - Full-Video Multi-Swing Analysis (Action Classifier)

    private func analyzeAllSwingsWithActionClassifier(
        at url: URL,
        progress: @escaping (Float) -> Void
    ) async throws -> [SwingDetectionResult] {
        progress(0.0)

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        print("📹 ActionClassifier multi-swing analysis: video duration=\(String(format: "%.2f", duration))s")

        let detector = ActionClassifierDetector()
        var detectedSwings: [SwingBounds] = []
        var framesProcessed = 0

        detector.onSwingDetected = { bounds in
            detectedSwings.append(bounds)
        }

        try await forEachVideoFrame(
            at: url,
            timeRangeSeconds: nil,
            targetFPS: offlineTargetFPS,
            progress: progress,
            process: { pixelBuffer, timestamp in
                framesProcessed += 1
                detector.processFrame(pixelBuffer, at: timestamp)
                return false  // Scan entire video
            }
        )

        print("📹 ActionClassifier: Processed \(framesProcessed) total frames, found \(detectedSwings.count) swing(s)")

        return detectedSwings.map { swing in
            SwingDetectionResult(
                impactTime: swing.impactTime,
                impactConfidence: swing.confidence,
                topOfBackswingTime: nil,
                topOfBackswingConfidence: 0,
                startTime: max(0, swing.startTime),
                endTime: min(duration, swing.endTime),
                phases: [],
                velocityProfile: []
            )
        }
    }

    // MARK: - Full-Video Multi-Swing Analysis (SwingNet)

    private func analyzeAllSwingsWithSwingNet(
        at url: URL,
        progress: @escaping (Float) -> Void
    ) async throws -> [SwingDetectionResult] {
        progress(0.0)

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        print("📹 SwingNet multi-swing analysis: video duration=\(String(format: "%.2f", duration))s")

        let detector = SwingNetDetector()
        var framesProcessed = 0

        try await forEachVideoFrame(
            at: url,
            timeRangeSeconds: nil,
            targetFPS: offlineTargetFPS,
            progress: progress,
            process: { pixelBuffer, timestamp in
                framesProcessed += 1
                detector.processFrame(pixelBuffer, at: timestamp)
                return false  // Never stop early — scan entire video
            }
        )

        print("📹 SwingNet: Processed \(framesProcessed) total frames, found \(detector.detectedSwings.count) swing(s)")

        return detector.detectedSwings.map { swing in
            SwingDetectionResult(
                impactTime: swing.impactTime,
                impactConfidence: swing.confidence,
                topOfBackswingTime: nil,
                topOfBackswingConfidence: 0,
                startTime: max(0, swing.startTime),
                endTime: min(duration, swing.endTime),
                phases: [],
                velocityProfile: []
            )
        }
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
