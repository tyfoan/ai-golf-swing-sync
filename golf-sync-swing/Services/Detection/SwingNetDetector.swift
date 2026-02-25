//
//  SwingNetDetector.swift
//  golf-sync-swing
//
//  Coordinates swing detection: inference → segmentation → wrist refinement.
//  Delegates each responsibility to a focused collaborator.
//
//  SwingNet outputs 9 per-frame probabilities:
//    0=Address, 1=Toe-up, 2=Mid-backswing, 3=Top,
//    4=Mid-downswing, 5=Impact, 6=Mid-follow-through, 7=Finish,
//    8=No-event
//

import CoreVideo
import os

// MARK: - Protocol

protocol SwingNetDetecting: Sendable {
    func detect(frames: [(CVPixelBuffer, TimeInterval)]) throws -> SwingDetectionResult
    func detectMultiple(frames: [(CVPixelBuffer, TimeInterval)]) throws -> [SwingDetectionResult]
}

// MARK: - Event Indices

enum SwingNetEvent: Int, CaseIterable {
    case address = 0
    case toeUp = 1
    case midBackswing = 2
    case top = 3
    case midDownswing = 4
    case impact = 5
    case midFollowThrough = 6
    case finish = 7
}

// MARK: - Implementation

final class SwingNetDetector: SwingNetDetecting {

    private let inference: SwingNetInferring
    private let segmenter: SwingSegmenting
    private let wristRefiner: WristRefining?

    init(
        inference: SwingNetInferring? = nil,
        segmenter: SwingSegmenting = SwingSegmenter(),
        wristRefiner: WristRefining? = WristRefinementService()
    ) throws {
        self.inference = try inference ?? SwingNetInference()
        self.segmenter = segmenter
        self.wristRefiner = wristRefiner
    }

    // MARK: - Single Swing

    func detect(frames: [(CVPixelBuffer, TimeInterval)]) throws -> SwingDetectionResult {
        guard !frames.isEmpty else {
            return noDetection
        }
        return try detectMultiple(frames: frames).first ?? noDetection
    }

    // MARK: - Multiple Swings

    func detectMultiple(frames: [(CVPixelBuffer, TimeInterval)]) throws -> [SwingDetectionResult] {
        guard !frames.isEmpty else { return [] }

        let probabilities = try inference.infer(frames: frames)
        let timestamps = frames.map(\.1)
        let results = segmenter.segment(probabilities: probabilities, timestamps: timestamps)

        return results.map { refineWithWrist(result: $0, frames: frames) }
    }

    // MARK: - Wrist Refinement

    private func refineWithWrist(result: SwingDetectionResult, frames: [(CVPixelBuffer, TimeInterval)]) -> SwingDetectionResult {
        guard let refiner = wristRefiner, let impactTime = result.impactTime else {
            return result
        }

        let refinedImpact = refiner.refineImpactTime(
            currentImpactTime: impactTime,
            frames: frames,
            searchWindow: 10
        )

        AppLogger.detection.info(
            "Wrist refinement: \(String(format: "%.3f", impactTime))s → \(String(format: "%.3f", refinedImpact))s"
        )

        return SwingDetectionResult(
            impactTime: refinedImpact,
            impactConfidence: result.impactConfidence,
            startTime: result.startTime,
            endTime: result.endTime
        )
    }

    // MARK: - Helpers

    private var noDetection: SwingDetectionResult {
        SwingDetectionResult(impactTime: nil, impactConfidence: 0, startTime: nil, endTime: nil)
    }
}
