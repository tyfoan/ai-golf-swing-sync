//
//  VideoFileSwingDetector.swift
//  golf-sync-swing
//
//  DEBUG-only. Replays a video file through the live detection pipeline
//  (DetectionOrchestrator): same detector, same thresholds, frames stamped with the
//  file's own times. Each frame is handed over only once the previous one has been
//  analysed. On a phone, Vision keeps up with the camera; on the simulator's CPU it
//  does not, and real-time feeding would drop most of a downswing's frames.
//
//  The shipping app detects only from the camera; the simulator has none, which is
//  why this path exists.
//

#if DEBUG

import Foundation

final class VideoFileSwingDetector {

    /// What the detector made of one file. `framesWithPose` separates "no swing in this
    /// video" from "Vision found no body at all" (the iOS simulator runtime ships no
    /// body-pose weights, so there every frame comes back empty).
    struct Report {
        let clips: [SwingClip]
        let framesAnalysed: Int
        let framesWithPose: Int
    }

    private let orchestrator: DetectionOrchestrator
    /// Time for the last frame's main-queue callbacks to land before the session is stopped.
    private let drainDelay: Duration
    private var detectedClips: [SwingClip] = []
    private var framesWithPose = 0

    init(orchestrator: DetectionOrchestrator = DetectionOrchestrator(), drainDelay: Duration = .seconds(1)) {
        self.orchestrator = orchestrator
        self.drainDelay = drainDelay
    }

    func detectSwings(in url: URL) async throws -> Report {
        let reader = try await VideoFileFrameReader(url: url)
        startDetection()
        defer { stopDetection() }
        let framesAnalysed = try await feedFrames(from: reader)
        try await Task.sleep(for: drainDelay)
        return Report(clips: detectedClips, framesAnalysed: framesAnalysed, framesWithPose: framesWithPose)
    }

    /// Hands every frame over in order, each after the detector has finished the last.
    private func feedFrames(from reader: VideoFileFrameReader) async throws -> Int {
        var count = 0
        while let frame = try reader.nextFrame() {
            orchestrator.processFrame(pixelBuffer: frame.pixelBuffer, timestamp: frame.time)
            try await waitUntilIdle()
            count += 1
        }
        return count
    }

    private func waitUntilIdle() async throws {
        while !orchestrator.isIdle {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func startDetection() {
        detectedClips = []
        framesWithPose = 0
        orchestrator.onSwingDetected = { [weak self] clip in self?.detectedClips.append(clip) }
        orchestrator.onPoseDetected = { [weak self] pose in
            if pose.jointCount > 0 { self?.framesWithPose += 1 }
        }
        orchestrator.start()
    }

    private func stopDetection() {
        orchestrator.stop()
        orchestrator.onSwingDetected = nil
        orchestrator.onPoseDetected = nil
    }
}

#endif
