//
//  SwingNetDetectorTests.swift
//  golf-sync-swingTests
//
//  Phase 3: Test SwingNet detection pipeline on real golf swing videos.
//

import CoreVideo
import Foundation
import Testing

@testable import golf_sync_swing

// MARK: - Test 1: SwingNet Model Loading

struct SwingNetModelTests {

    @Test func modelLoadsSuccessfully() throws {
        let detector = try SwingNetDetector()
        #expect(detector != nil, "SwingNetDetector should load without error")
    }

    @Test func emptyFramesReturnNoDetection() throws {
        let detector = try SwingNetDetector()
        let result = try detector.detect(frames: [])
        #expect(result.impactTime == nil)
        #expect(result.impactConfidence == 0)
    }
}

// MARK: - Test 2: GolfDB Test Video

struct SwingNetDetectionTests {

    /// Known PyTorch reference values from Phase 1 validation.
    /// test_video.mp4: 264 frames, 30fps, impact at frame 143 (4.77s).
    static let testVideoPath = "/Users/aleksanderogurtsov/Desktop/test/golf-sync-swing/ml-training/golfdb_repo/test_video.mp4"
    static let expectedImpactTimeSeconds = 4.77
    static let toleranceSeconds = 0.15 // ±4.5 frames at 30fps

    @Test func detectsImpactInGolfDBTestVideo() async throws {
        let url = URL(fileURLWithPath: Self.testVideoPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Issue.record("Test video not found at: \(Self.testVideoPath)")
            return
        }

        // Extract frames
        let frames = try await extractFrames(from: url, targetFPS: 30)
        #expect(frames.count > 200, "Expected ~264 frames, got \(frames.count)")

        // Run detection
        let detector = try SwingNetDetector()
        let result = try detector.detect(frames: frames)

        // Verify impact detected
        #expect(result.hasValidDetection, "Impact should be detected with confidence > 0.3")
        #expect(result.impactConfidence > 0.7, "Impact confidence should be high, got \(result.impactConfidence)")

        // Verify impact time matches PyTorch reference (±4.5 frames)
        guard let impactTime = result.impactTime else {
            Issue.record("Impact time is nil despite hasValidDetection")
            return
        }

        let error = abs(impactTime - Self.expectedImpactTimeSeconds)
        #expect(error < Self.toleranceSeconds,
                "Impact at \(String(format: "%.2f", impactTime))s, expected \(Self.expectedImpactTimeSeconds)s (error: \(String(format: "%.3f", error))s)")

        // Verify start/end times are reasonable
        if let startTime = result.startTime, let endTime = result.endTime {
            #expect(startTime < impactTime, "Start (\(startTime)) should be before impact (\(impactTime))")
            #expect(endTime > impactTime, "End (\(endTime)) should be after impact (\(impactTime))")
        }
    }

    @Test func personCropperProducesValidBuffers() async throws {
        let url = URL(fileURLWithPath: Self.testVideoPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Issue.record("Test video not found")
            return
        }

        let cropper = PersonCropper()
        var croppedCount = 0
        let iterator = VideoFrameIterator()

        try await iterator.forEachFrame(
            at: url,
            timeRangeSeconds: nil,
            targetFPS: 30,
            progress: { _ in },
            process: { pixelBuffer, _ in
                let cropped = cropper.crop(from: pixelBuffer)
                let width = CVPixelBufferGetWidth(cropped)
                let height = CVPixelBufferGetHeight(cropped)
                #expect(width == 160, "Cropped width should be 160, got \(width)")
                #expect(height == 160, "Cropped height should be 160, got \(height)")
                croppedCount += 1
                return croppedCount >= 5 // Only check first 5 frames
            }
        )

        #expect(croppedCount == 5, "Should have cropped 5 frames")
    }

    // MARK: - Frame Extraction Helper

    private func extractFrames(
        from url: URL,
        targetFPS: Double
    ) async throws -> [(CVPixelBuffer, TimeInterval)] {
        var frames: [(CVPixelBuffer, TimeInterval)] = []
        let cropper = PersonCropper()
        let iterator = VideoFrameIterator()

        try await iterator.forEachFrame(
            at: url,
            timeRangeSeconds: nil,
            targetFPS: targetFPS,
            progress: { _ in },
            process: { pixelBuffer, timestamp in
                let cropped = cropper.crop(from: pixelBuffer)
                frames.append((cropped, timestamp))
                return false
            }
        )

        return frames
    }
}

// MARK: - Test 3: Multi-Video GolfDB Validation

struct SwingNetMultiVideoTests {

    /// GolfDB ground truth: [start, address, toe-up, mid-backswing, top, mid-downswing, impact, mid-follow-through, finish, end]
    /// Event index 6 (0-based) = impact frame number in the full video.
    struct TestCase {
        let name: String
        let path: String
        let fps: Double
        let impactFrame: Int
        let swingStart: Int
        let swingEnd: Int

        var impactTimeSeconds: Double { Double(impactFrame) / fps }
        var extractionRange: ClosedRange<TimeInterval> {
            let start = max(0, Double(swingStart) / fps - 1.0)
            let end = Double(swingEnd) / fps + 1.0
            return start...end
        }
    }

    static let videosDir = "/Users/aleksanderogurtsov/Desktop/test/golf-sync-swing/ml-training/youtube_videos"
    static let toleranceSeconds = 0.25 // ±7.5 frames at 30fps — reasonable for full video extraction

    static let testCases = [
        TestCase(name: "CfCODKOZSg4", path: "\(videosDir)/CfCODKOZSg4.mp4", fps: 30, impactFrame: 172, swingStart: 61, swingEnd: 226),
        TestCase(name: "DN8F1bG76Vk", path: "\(videosDir)/DN8F1bG76Vk.mp4", fps: 30, impactFrame: 227, swingStart: 151, swingEnd: 314),
        TestCase(name: "BlDsHA-HNlI", path: "\(videosDir)/BlDsHA-HNlI.mp4", fps: 30, impactFrame: 398, swingStart: 331, swingEnd: 475),
    ]

    @Test(arguments: testCases.indices)
    func detectsImpactInGolfDBVideo(index: Int) async throws {
        let testCase = Self.testCases[index]
        let url = URL(fileURLWithPath: testCase.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Issue.record("Video not found: \(testCase.name)")
            return
        }

        let frames = try await extractFrames(from: url, timeRange: testCase.extractionRange, targetFPS: 30)
        #expect(frames.count > 30, "\(testCase.name): Expected 50+ frames, got \(frames.count)")

        let detector = try SwingNetDetector()
        let result = try detector.detect(frames: frames)

        #expect(result.hasValidDetection, "\(testCase.name): Should detect a swing")

        guard let impactTime = result.impactTime else {
            Issue.record("\(testCase.name): Impact time is nil")
            return
        }

        let expectedTime = testCase.impactTimeSeconds
        let error = abs(impactTime - expectedTime)
        #expect(error < Self.toleranceSeconds,
                "\(testCase.name): Impact at \(String(format: "%.2f", impactTime))s, expected \(String(format: "%.2f", expectedTime))s (error: \(String(format: "%.3f", error))s)")
    }

    private func extractFrames(
        from url: URL,
        timeRange: ClosedRange<TimeInterval>,
        targetFPS: Double
    ) async throws -> [(CVPixelBuffer, TimeInterval)] {
        var frames: [(CVPixelBuffer, TimeInterval)] = []
        let cropper = PersonCropper()
        let iterator = VideoFrameIterator()

        try await iterator.forEachFrame(
            at: url,
            timeRangeSeconds: timeRange,
            targetFPS: targetFPS,
            progress: { _ in },
            process: { pixelBuffer, timestamp in
                let cropped = cropper.crop(from: pixelBuffer)
                frames.append((cropped, timestamp))
                return false
            }
        )

        return frames
    }
}

// MARK: - Test 4: End-to-End Sync Offset

struct SwingNetSyncTests {

    /// Verify that sync offset between two videos is correct.
    /// Video 1: test_video.mp4 — impact at ~4.77s
    /// Video 2: CfCODKOZSg4 — impact at ~5.73s (frame 172 @ 30fps)
    @Test func syncOffsetMatchesExpected() async throws {
        let video1URL = URL(fileURLWithPath: SwingNetDetectionTests.testVideoPath)
        let video2Path = "\(SwingNetMultiVideoTests.videosDir)/CfCODKOZSg4.mp4"
        let video2URL = URL(fileURLWithPath: video2Path)

        guard FileManager.default.fileExists(atPath: video1URL.path),
              FileManager.default.fileExists(atPath: video2URL.path) else {
            Issue.record("Test videos not found")
            return
        }

        let detector = try SwingNetDetector()
        let cropper = PersonCropper()
        let iterator = VideoFrameIterator()

        // Detect impact in video 1 (full extraction — short video)
        let frames1 = try await extractAllFrames(from: video1URL, cropper: cropper, iterator: iterator)
        let result1 = try detector.detect(frames: frames1)

        // Detect impact in video 2 (extract swing region only)
        let range2: ClosedRange<TimeInterval> = 1.0...8.5
        let frames2 = try await extractFrames(from: video2URL, timeRange: range2, cropper: cropper, iterator: iterator)
        let result2 = try detector.detect(frames: frames2)

        guard let impact1 = result1.impactTime, let impact2 = result2.impactTime else {
            Issue.record("Both videos should detect impact: v1=\(result1.impactTime as Any), v2=\(result2.impactTime as Any)")
            return
        }

        // Sync offset = contact1 - contact2 (how ComparisonViewModel calculates it)
        let syncOffset = impact1 - impact2
        let expectedOffset = 4.77 - 5.73 // test_video impact minus CfCODKOZSg4 impact
        let offsetError = abs(syncOffset - expectedOffset)

        #expect(offsetError < 0.5, "Sync offset \(String(format: "%.2f", syncOffset))s, expected ~\(String(format: "%.2f", expectedOffset))s (error: \(String(format: "%.3f", offsetError))s)")
    }

    private func extractAllFrames(
        from url: URL,
        cropper: PersonCropper,
        iterator: VideoFrameIterator
    ) async throws -> [(CVPixelBuffer, TimeInterval)] {
        var frames: [(CVPixelBuffer, TimeInterval)] = []

        try await iterator.forEachFrame(
            at: url,
            timeRangeSeconds: nil,
            targetFPS: 30,
            progress: { _ in },
            process: { pixelBuffer, timestamp in
                let cropped = cropper.crop(from: pixelBuffer)
                frames.append((cropped, timestamp))
                return false
            }
        )

        return frames
    }

    private func extractFrames(
        from url: URL,
        timeRange: ClosedRange<TimeInterval>,
        cropper: PersonCropper,
        iterator: VideoFrameIterator
    ) async throws -> [(CVPixelBuffer, TimeInterval)] {
        var frames: [(CVPixelBuffer, TimeInterval)] = []

        try await iterator.forEachFrame(
            at: url,
            timeRangeSeconds: timeRange,
            targetFPS: 30,
            progress: { _ in },
            process: { pixelBuffer, timestamp in
                let cropped = cropper.crop(from: pixelBuffer)
                frames.append((cropped, timestamp))
                return false
            }
        )

        return frames
    }
}

// MARK: - Test 5: Edge Cases

struct SwingNetEdgeCaseTests {

    @Test func shortVideoHandledGracefully() async throws {
        // Create a minimal set of frames (fewer than 64)
        let detector = try SwingNetDetector()

        // Create synthetic blank frames
        var frames: [(CVPixelBuffer, TimeInterval)] = []
        for i in 0..<10 {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 160, 160, kCVPixelFormatType_32BGRA, nil, &buffer)
            if let buffer {
                frames.append((buffer, Double(i) / 30.0))
            }
        }

        // Should not crash — may or may not detect a swing
        let result = try detector.detect(frames: frames)
        #expect(result != nil, "Should return a result even for short video")
    }
}
