//
//  SwingNetAnalysisRunner.swift
//  golf-sync-swing
//
//  Orchestrates end-to-end swing analysis: extracts video frames,
//  crops each to 160x160 person-centered, runs SwingNet inference,
//  and produces SwingMarker models for SwiftData.
//

import CoreVideo
import Foundation
import os
import SwiftData

// MARK: - Protocol

protocol SwingAnalysisRunning {
    func analyze(video: SwingVideo, context: ModelContext, progress: @escaping (Float, String) -> Void) async throws
}

// MARK: - Implementation

@MainActor
final class SwingNetAnalysisRunner: SwingAnalysisRunning {

    private let frameIterator: VideoFrameIterator
    private let personCropper: PersonCropping
    private let detector: SwingNetDetecting

    init(
        frameIterator: VideoFrameIterator = VideoFrameIterator(),
        personCropper: PersonCropping = PersonCropper(),
        detector: SwingNetDetecting? = nil
    ) {
        self.frameIterator = frameIterator
        self.personCropper = personCropper

        if let detector {
            self.detector = detector
        } else {
            do {
                self.detector = try SwingNetDetector()
            } catch {
                AppLogger.detection.error("Failed to load SwingNet model: \(error.localizedDescription)")
                fatalError("SwingNet model missing from bundle: \(error)")
            }
        }
    }

    // MARK: - Analysis

    nonisolated func analyze(
        video: SwingVideo,
        context: ModelContext,
        progress: @escaping (Float, String) -> Void
    ) async throws {
        let url = video.localURL
        let fps = video.fps

        AppLogger.detection.info("Starting SwingNet analysis: \(url.lastPathComponent), \(fps) fps")
        progress(0, "Extracting frames...")

        let frames = try await extractFrames(url: url, targetFPS: min(fps, 30), progress: progress)

        guard !frames.isEmpty else {
            throw SyncEngineError.analysisFailure("No frames extracted from video")
        }

        AppLogger.detection.info("Extracted \(frames.count) frames, running detection...")
        progress(0.7, "Detecting swing events...")

        let result = try detector.detect(frames: frames)
        progress(0.9, "Saving results...")

        await saveResult(result, video: video, context: context)

        AppLogger.detection.info("Analysis complete: impact=\(result.impactTime.map { String(format: "%.2f", $0) } ?? "none")")
        progress(1.0, result.hasValidDetection ? "Swing detected!" : "No swing detected")
    }

    // MARK: - Frame Extraction

    private nonisolated func extractFrames(
        url: URL,
        targetFPS: Double,
        progress: @escaping (Float, String) -> Void
    ) async throws -> [(CVPixelBuffer, TimeInterval)] {
        var frames: [(CVPixelBuffer, TimeInterval)] = []

        try await frameIterator.forEachFrame(
            at: url,
            timeRangeSeconds: nil,
            targetFPS: targetFPS,
            progress: { fraction in
                progress(fraction * 0.7, "Extracting frames...")
            },
            process: { pixelBuffer, timestamp in
                let cropped = personCropper.crop(from: pixelBuffer)
                frames.append((cropped, timestamp))
                return false
            }
        )

        return frames
    }

    // MARK: - Persistence

    private func saveResult(_ result: SwingDetectionResult, video: SwingVideo, context: ModelContext) {
        guard result.hasValidDetection else {
            video.hasBeenAnalyzed = true
            video.analysisDate = Date()
            return
        }

        let marker = SwingMarker(from: result)
        marker.video = video
        video.swings.append(marker)
        context.insert(marker)

        video.hasBeenAnalyzed = true
        video.analysisDate = Date()
    }
}
