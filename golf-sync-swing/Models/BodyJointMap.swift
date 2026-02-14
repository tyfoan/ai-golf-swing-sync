//
//  BodyJointMap.swift
//  golf-sync-swing
//
//  Value types representing body skeleton data extracted from Vision framework.
//  BodyJoint holds a normalized position (0...1) and confidence score.
//  BodyJointMap is the complete set of detected joints for a single frame.
//

import Vision

struct BodyJoint: Sendable {
    let position: CGPoint
    let confidence: Float
}

struct BodyJointMap: Sendable {
    let joints: [VNHumanBodyPoseObservation.JointName: BodyJoint]
    let timestamp: TimeInterval

    var jointCount: Int { joints.count }

    static let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        // Head
        (.nose, .neck),
        // Torso
        (.neck, .leftShoulder),
        (.neck, .rightShoulder),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        // Left arm
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        // Right arm
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        // Left leg
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        // Right leg
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
        // Shoulder-to-shoulder
        (.leftShoulder, .rightShoulder),
    ]
}
