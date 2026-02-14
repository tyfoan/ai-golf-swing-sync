//
//  PoseExtractor.swift
//  golf-sync-swing
//
//  Extracts body pose keypoints from a video frame using Vision framework.
//  Returns both MLMultiArray (for classifier) and BodyJointMap (for skeleton UI).
//

import CoreML
import Vision

struct PoseExtractionResult: Sendable {
    let multiArray: MLMultiArray
    let jointMap: BodyJointMap?
}

protocol PoseExtracting: Sendable {
    func extractPose(from pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) -> PoseExtractionResult?
}

final class PoseExtractor: PoseExtracting, @unchecked Sendable {

    private let minimumJointConfidence: Float = 0.35
    private let minimumJointCount: Int = 8

    private let trackedJoints: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .neck,
        .leftShoulder, .rightShoulder,
        .leftElbow, .rightElbow,
        .leftWrist, .rightWrist,
        .leftHip, .rightHip,
        .leftKnee, .rightKnee,
        .leftAnkle, .rightAnkle,
    ]

    func extractPose(from pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) -> PoseExtractionResult? {
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

        guard let multiArray = try? observation.keypointsMultiArray() else {
            return nil
        }

        let jointMap = buildJointMap(from: observation, at: timestamp)
        return PoseExtractionResult(multiArray: multiArray, jointMap: jointMap)
    }

    // MARK: - Joint Map Construction

    private func buildJointMap(from observation: VNHumanBodyPoseObservation, at timestamp: TimeInterval) -> BodyJointMap? {
        var joints: [VNHumanBodyPoseObservation.JointName: BodyJoint] = [:]

        for jointName in trackedJoints {
            guard let point = try? observation.recognizedPoint(jointName),
                  point.confidence >= minimumJointConfidence else { continue }

            // Vision y-axis is bottom-up; flip to top-down for UIKit/SwiftUI
            let position = CGPoint(x: point.location.x, y: 1 - point.location.y)
            joints[jointName] = BodyJoint(position: position, confidence: point.confidence)
        }

        guard joints.count >= minimumJointCount else { return nil }

        return BodyJointMap(joints: joints, timestamp: timestamp)
    }
}
