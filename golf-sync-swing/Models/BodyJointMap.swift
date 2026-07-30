//
//  BodyJointMap.swift
//  golf-sync-swing
//
//  Value types representing body skeleton data extracted from Vision framework.
//  BodyJoint holds a normalized position (0...1) and confidence score.
//  BodyJointMap is the complete set of detected joints for a single frame.
//
//  It is also where the skeleton itself is defined: `connections` is the one list of bones,
//  and both of its clients derive from it — `SkeletonOverlayView` strokes it, `PoseDetector`
//  extracts the joints it names. Neither keeps a list of its own.
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

    /// Bridges the detection pipeline's `PoseFrame` into the drawing layer's shape. Keeps
    /// `SkeletonOverlayView` unaware of the detection types, and the detection pipeline
    /// unaware of the view.
    init(frame: PoseFrame) {
        self.joints = frame.joints.mapValues {
            BodyJoint(position: CGPoint(x: $0.x, y: $0.y), confidence: $0.confidence)
        }
        self.timestamp = frame.timestamp
    }

    init(joints: [VNHumanBodyPoseObservation.JointName: BodyJoint], timestamp: TimeInterval) {
        self.joints = joints
        self.timestamp = timestamp
    }

    /// One bone: the two joints it spans. Naming the pair is what lets `skeletonJoints` derive
    /// itself from `connections` legibly.
    typealias Bone = (from: VNHumanBodyPoseObservation.JointName, to: VNHumanBodyPoseObservation.JointName)

    /// The skeleton, defined once. Adding or removing a bone here is the whole edit:
    /// `SkeletonOverlayView` strokes exactly this list, and `PoseDetector` extracts exactly the
    /// joints it lands on by way of `skeletonJoints`.
    ///
    /// That second half used to be an independent literal in `PoseDetector`, and the two
    /// drifted: the knees and the nose were connected here and never extracted, so all four
    /// leg bones and the head bone were permanently undrawable — every one of them missing an
    /// endpoint. Derivation makes that class of bug unrepresentable: a bone can no longer name
    /// a joint nobody asked Vision for.
    static let connections: [Bone] = [
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

    /// Every joint some bone lands on. Derived, never authored: this is the list `PoseDetector`
    /// extracts, so connecting a bone above is sufficient to make it appear on screen.
    static let skeletonJoints: Set<VNHumanBodyPoseObservation.JointName> =
        Set(connections.flatMap { [$0.from, $0.to] })
}
