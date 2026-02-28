//
//  PoseFrame.swift
//  golf-sync-swing
//
//  A single frame of body pose data extracted from Vision.
//  Flows through the detection pipeline: PoseDetector → SwingClassifier/PoseHeuristics → SwingStateMachine.
//

import Foundation
import Vision

struct PoseFrame: Sendable {
    let timestamp: TimeInterval
    let joints: [VNHumanBodyPoseObservation.JointName: JointPosition]
    let observation: VNHumanBodyPoseObservation?

    struct JointPosition: Sendable, Codable {
        let x: CGFloat
        let y: CGFloat
        let confidence: Float
    }

    init(
        timestamp: TimeInterval,
        joints: [VNHumanBodyPoseObservation.JointName: JointPosition],
        observation: VNHumanBodyPoseObservation? = nil
    ) {
        self.timestamp = timestamp
        self.joints = joints
        self.observation = observation
    }
}

// MARK: - Convenience Accessors

extension PoseFrame {

    func joint(_ name: VNHumanBodyPoseObservation.JointName) -> JointPosition? {
        joints[name]
    }

    var leftWrist: JointPosition? { joint(.leftWrist) }
    var rightWrist: JointPosition? { joint(.rightWrist) }
    var leftShoulder: JointPosition? { joint(.leftShoulder) }
    var rightShoulder: JointPosition? { joint(.rightShoulder) }
    var leftHip: JointPosition? { joint(.leftHip) }
    var rightHip: JointPosition? { joint(.rightHip) }
    var neck: JointPosition? { joint(.neck) }

    /// The lowest wrist y-position (Vision: 0=bottom, 1=top).
    /// Returns the wrist with smaller y value (closer to ground).
    var lowestWristY: CGFloat? {
        let candidates = [leftWrist, rightWrist].compactMap { $0 }
            .filter { $0.confidence > 0.3 }
        return candidates.map(\.y).min()
    }

    /// Hip center x-coordinate (average of both hips).
    var hipCenterX: CGFloat? {
        guard let left = leftHip, let right = rightHip,
              left.confidence > 0.3, right.confidence > 0.3 else { return nil }
        return (left.x + right.x) / 2.0
    }

    /// Shoulder rotation angle in radians (atan2 of shoulder line).
    var shoulderAngle: CGFloat? {
        guard let left = leftShoulder, let right = rightShoulder,
              left.confidence > 0.3, right.confidence > 0.3 else { return nil }
        return atan2(right.y - left.y, right.x - left.x)
    }
}
