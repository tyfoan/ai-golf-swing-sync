//
//  PoseExtractor.swift
//  golf-sync-swing
//
//  Extracts body pose keypoints from a video frame using Vision framework.
//

import CoreML
import Vision

protocol PoseExtracting: Sendable {
    func extractPose(from pixelBuffer: CVPixelBuffer) -> MLMultiArray?
}

final class PoseExtractor: PoseExtracting, @unchecked Sendable {

    func extractPose(from pixelBuffer: CVPixelBuffer) -> MLMultiArray? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else {
            return nil
        }

        do {
            return try observation.keypointsMultiArray()
        } catch {
            return nil
        }
    }
}
