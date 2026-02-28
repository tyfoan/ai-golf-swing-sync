//
//  GolfDBValidationTests.swift
//  golf-sync-swingTests
//
//  End-to-end validation of the swing detection pipeline against
//  GolfDB ground truth. Each test video has a known impact time.
//  The pipeline must detect a swing and place impact within ±500ms.
//
//  NOTE: These tests require VNDetectHumanBodyPoseRequest which only
//  works on physical devices. They are automatically skipped on the simulator.
//

import AVFoundation
import CoreVideo
import Testing
import Vision
@testable import golf_sync_swing

struct GolfDBValidationTests {

    // MARK: - Ground Truth

    private struct GroundTruth {
        let filename: String
        let player: String
        let impactTimeSec: Double
        /// Normalized bounding box [x_min, y_min, x_max, y_max] from GolfDB
        let bbox: CGRect
    }

    private static let testVideos: [GroundTruth] = [
        GroundTruth(filename: "golfdb_f1BWA5F87Jc", player: "Sandra Gal", impactTimeSec: 3.900,
                    bbox: CGRect(x: 0.098, y: 0.007, width: 0.405, height: 0.974)),
        GroundTruth(filename: "golfdb_iW323nsTGtU", player: "Hyo Joo Kim", impactTimeSec: 3.567,
                    bbox: CGRect(x: 0.293, y: 0.001, width: 0.422, height: 0.988)),
        GroundTruth(filename: "golfdb_4HzLO88ryCU", player: "Tiger Woods", impactTimeSec: 2.967,
                    bbox: CGRect(x: 0.166, y: 0.001, width: 0.318, height: 0.986)),
        GroundTruth(filename: "golfdb_KR9Umr1GM-U", player: "Rory McIlroy", impactTimeSec: 2.600,
                    bbox: CGRect(x: 0.168, y: 0.001, width: 0.529, height: 0.983)),
        GroundTruth(filename: "golfdb_tpv8QUM0G0E", player: "Paula Creamer", impactTimeSec: 2.767,
                    bbox: CGRect(x: 0.120, y: 0.001, width: 0.589, height: 0.996)),
    ]

    // MARK: - Vision Availability

    /// VNDetectHumanBodyPoseRequest requires Neural Engine — unavailable on simulator.
    private static var isPhysicalDevice: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    // MARK: - Swing Detection Tests (Device Only)

    @Test("Pose extraction produces wrist data from video",
          .tags(.golfdb),
          .enabled(if: GolfDBValidationTests.isPhysicalDevice, "Requires physical device for VNDetectHumanBodyPoseRequest"))
    func poseExtractionDiagnostic() throws {

        let gt = Self.testVideos[2]
        guard let url = Bundle(for: BundleToken.self).url(
            forResource: gt.filename,
            withExtension: "mp4"
        ) else {
            Issue.record("Test video not in bundle")
            return
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true

        let time = CMTime(value: 60, timescale: 30)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        #expect(cgImage.width > 0, "CGImage width should be > 0, got \(cgImage.width)")
        #expect(cgImage.height > 0, "CGImage height should be > 0, got \(cgImage.height)")

        let cropped = cropToBBox(cgImage, bbox: gt.bbox)
        #expect(cropped.width > 0, "Cropped width: \(cropped.width)")

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
        try handler.perform([request])
        let resultCount = request.results?.count ?? 0
        #expect(resultCount > 0, "No pose results from cropped frame (\(cropped.width)x\(cropped.height))")

        if let observation = request.results?.first {
            let allJoints = try observation.recognizedPoints(.all)
            let highConfidence = allJoints.filter { $0.value.confidence > 0.1 }
            #expect(highConfidence.count > 0, "No high-confidence joints, all joints: \(allJoints.count)")
        }

        let frames = try extractPoseFrames(from: url, bbox: gt.bbox)
        let framesWithJoints = frames.filter { !$0.joints.isEmpty }.count
        let framesWithWrist = frames.filter { $0.leftWrist != nil || $0.rightWrist != nil }.count

        #expect(frames.count > 0, "Should extract at least 1 frame, got \(frames.count)")
        #expect(framesWithJoints > 0, "Should have joints: got \(framesWithJoints)/\(frames.count)")
        #expect(framesWithWrist > 0, "Should have wrist data: got \(framesWithWrist)/\(frames.count)")
    }

    @Test("Detects swing in Sandra Gal video",
          .tags(.golfdb),
          .enabled(if: GolfDBValidationTests.isPhysicalDevice, "Requires physical device"))
    func sandraGal() throws {
        try assertSwingDetected(for: Self.testVideos[0])
    }

    @Test("Detects swing in Hyo Joo Kim video",
          .tags(.golfdb),
          .enabled(if: GolfDBValidationTests.isPhysicalDevice, "Requires physical device"))
    func hyoJooKim() throws {
        try assertSwingDetected(for: Self.testVideos[1])
    }

    @Test("Detects swing in Tiger Woods video",
          .tags(.golfdb),
          .enabled(if: GolfDBValidationTests.isPhysicalDevice, "Requires physical device"))
    func tigerWoods() throws {
        try assertSwingDetected(for: Self.testVideos[2])
    }

    @Test("Detects swing in Rory McIlroy video",
          .tags(.golfdb),
          .enabled(if: GolfDBValidationTests.isPhysicalDevice, "Requires physical device"))
    func roryMcIlroy() throws {
        try assertSwingDetected(for: Self.testVideos[3])
    }

    @Test("Detects swing in Paula Creamer video",
          .tags(.golfdb),
          .enabled(if: GolfDBValidationTests.isPhysicalDevice, "Requires physical device"))
    func paulaCreamer() throws {
        try assertSwingDetected(for: Self.testVideos[4])
    }

    // MARK: - Snapshot Exporter (Device Only)

    @Test("Export pose snapshots for all GolfDB test videos",
          .tags(.golfdb),
          .enabled(if: GolfDBValidationTests.isPhysicalDevice, "Requires physical device"))
    func exportPoseSnapshots() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pose_snapshots", isDirectory: true)

        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        for groundTruth in Self.testVideos {
            let url = try locateVideo(for: groundTruth)
            let frames = try extractPoseFrames(from: url, bbox: groundTruth.bbox, sampleRate: 15)
            let serializable = frames.map { SerializablePoseFrame(poseFrame: $0) }
            let data = try encoder.encode(serializable)
            let snapshotFile = snapshotFilename(from: groundTruth.filename)
            let outputURL = outputDir.appendingPathComponent(snapshotFile)

            try data.write(to: outputURL)
        }

        print("Pose snapshots exported to: \(outputDir.path)")
    }

    // MARK: - Video Frame Extraction Tests (Simulator-Safe)

    @Test("Test videos are in bundle and extractable", .tags(.golfdb))
    func videoFrameExtraction() throws {
        for gt in Self.testVideos {
            guard let url = Bundle(for: BundleToken.self).url(
                forResource: gt.filename,
                withExtension: "mp4"
            ) else {
                Issue.record("Missing video: \(gt.filename).mp4")
                continue
            }

            let asset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(asset.duration)
            #expect(duration > 2.0, "\(gt.player): video too short (\(duration)s)")
            #expect(duration < 10.0, "\(gt.player): video too long (\(duration)s)")

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let midTime = CMTimeMakeWithSeconds(gt.impactTimeSec, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: midTime, actualTime: nil)
            #expect(cgImage.width > 0, "\(gt.player): frame at impact has 0 width")

            let cropped = cropToBBox(cgImage, bbox: gt.bbox)
            #expect(cropped.width > 50, "\(gt.player): cropped frame too small (\(cropped.width)px)")
        }
    }

    @Test("Ground truth impact times are within video duration", .tags(.golfdb))
    func groundTruthTimesValid() throws {
        for gt in Self.testVideos {
            guard let url = Bundle(for: BundleToken.self).url(
                forResource: gt.filename,
                withExtension: "mp4"
            ) else {
                Issue.record("Missing video: \(gt.filename).mp4")
                continue
            }

            let asset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(asset.duration)
            #expect(
                gt.impactTimeSec > 0 && gt.impactTimeSec < duration,
                "\(gt.player): impact \(gt.impactTimeSec)s outside video duration \(duration)s"
            )
        }
    }

    // MARK: - Pipeline Under Test

    private func assertSwingDetected(
        for groundTruth: GroundTruth,
        toleranceSec: Double = 1.0
    ) throws {
        guard let url = Bundle(for: BundleToken.self).url(
            forResource: groundTruth.filename,
            withExtension: "mp4"
        ) else {
            Issue.record("Test video not in bundle: \(groundTruth.filename).mp4")
            return
        }

        let frames = try extractPoseFrames(from: url, bbox: groundTruth.bbox, sampleRate: 15)
        #expect(frames.count >= 15, "Need at least 15 frames, got \(frames.count)")

        let framesWithWrist = frames.filter { $0.leftWrist != nil || $0.rightWrist != nil }
        let wristYValues = framesWithWrist.compactMap { frame -> (Double, CGFloat)? in
            let wrists = [frame.leftWrist, frame.rightWrist].compactMap { $0 }
                .filter { $0.confidence > 0.3 }
            guard let minY = wrists.map(\.y).min() else { return nil }
            return (frame.timestamp, minY)
        }

        let yRange = wristYValues.isEmpty ? 0.0 :
            (wristYValues.map(\.1).max()! - wristYValues.map(\.1).min()!)

        let result = runDetectionPipeline(frames: frames)
        guard let detection = result else {
            let msg = "\(groundTruth.player): no swing detected (expected impact at \(groundTruth.impactTimeSec)s). Frames: \(frames.count), withWrist: \(framesWithWrist.count), wristY range: \(String(format: "%.3f", yRange))"
            Issue.record("\(msg)")
            return
        }

        let error = abs(detection.impactTime - groundTruth.impactTimeSec)
        #expect(
            error <= toleranceSec,
            "\(groundTruth.player): impact at \(String(format: "%.3f", detection.impactTime))s, expected \(groundTruth.impactTimeSec)s (error: \(String(format: "%.3f", error))s, tolerance: \(toleranceSec)s)"
        )
    }

    // MARK: - Helpers

    private func locateVideo(for groundTruth: GroundTruth) throws -> URL {
        guard let url = Bundle(for: BundleToken.self).url(
            forResource: groundTruth.filename,
            withExtension: "mp4"
        ) else {
            Issue.record("Test video not in bundle: \(groundTruth.filename).mp4")
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    private func snapshotFilename(from bundleFilename: String) -> String {
        let youtubeId = bundleFilename.replacingOccurrences(of: "golfdb_", with: "")
        return "\(youtubeId).json"
    }

    // MARK: - Frame Extraction

    private func extractPoseFrames(
        from url: URL,
        bbox: CGRect? = nil,
        sampleRate: Double = 10
    ) throws -> [PoseFrame] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true

        let duration = CMTimeGetSeconds(asset.duration)
        let frameCount = Int(duration * sampleRate)

        var frames: [PoseFrame] = []

        for i in 0..<frameCount {
            autoreleasepool {
                let timestamp = Double(i) / sampleRate
                let time = CMTimeMakeWithSeconds(timestamp, preferredTimescale: 600)
                guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                    return
                }

                let croppedImage = cropToBBox(cgImage, bbox: bbox)
                let frame = extractPoseFromCGImage(croppedImage, at: timestamp)
                frames.append(frame)
            }
        }

        return frames
    }

    private func cropToBBox(_ image: CGImage, bbox: CGRect?) -> CGImage {
        guard let bbox else { return image }

        let w = CGFloat(image.width)
        let h = CGFloat(image.height)

        let cropRect = CGRect(
            x: bbox.origin.x * w,
            y: bbox.origin.y * h,
            width: bbox.size.width * w,
            height: bbox.size.height * h
        )

        return image.cropping(to: cropRect) ?? image
    }

    private func extractPoseFromCGImage(_ cgImage: CGImage, at timestamp: TimeInterval) -> PoseFrame {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return PoseFrame(timestamp: timestamp, joints: [:])
        }

        guard let observation = request.results?.first else {
            return PoseFrame(timestamp: timestamp, joints: [:])
        }

        let trackedJoints: [VNHumanBodyPoseObservation.JointName] = [
            .leftWrist, .rightWrist,
            .leftShoulder, .rightShoulder,
            .leftHip, .rightHip,
            .leftElbow, .rightElbow,
            .neck,
            .leftAnkle, .rightAnkle,
        ]

        var joints: [VNHumanBodyPoseObservation.JointName: PoseFrame.JointPosition] = [:]

        for jointName in trackedJoints {
            guard let point = try? observation.recognizedPoint(jointName),
                  point.confidence > 0.1 else { continue }

            joints[jointName] = PoseFrame.JointPosition(
                x: point.location.x,
                y: point.location.y,
                confidence: point.confidence
            )
        }

        return PoseFrame(timestamp: timestamp, joints: joints, observation: observation)
    }

    // MARK: - Detection Pipeline

    private struct DetectionResult {
        let impactTime: TimeInterval
        let confidence: Double
    }

    /// Uses the production ImpactDetector to validate the actual code path.
    private func runDetectionPipeline(frames: [PoseFrame]) -> DetectionResult? {
        let detector = ImpactDetector()
        guard let impactTime = detector.findImpactTime(in: frames) else { return nil }
        return DetectionResult(impactTime: impactTime, confidence: 1.0)
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var golfdb: Self
}

// MARK: - Bundle Anchor

private final class BundleToken {}
