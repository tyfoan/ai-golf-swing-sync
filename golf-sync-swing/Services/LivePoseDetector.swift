//
//  LivePoseDetector.swift
//  golf-sync-swing
//
//  Real-time body pose detection using Vision framework
//

import Vision
import AVFoundation
import CoreImage
import Combine

/// Body pose data for a single frame
@preconcurrency
struct BodyPose: Sendable {
    nonisolated let timestamp: TimeInterval
    nonisolated let joints: [String: CGPoint]
    nonisolated let confidence: Float

    /// Get position for a specific joint
    nonisolated func position(for jointName: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        joints[jointName.rawValue.rawValue]
    }

    /// Get wrist position (prefers right wrist)
    nonisolated var wristPosition: CGPoint? {
        joints[VNHumanBodyPoseObservation.JointName.rightWrist.rawValue.rawValue]
            ?? joints[VNHumanBodyPoseObservation.JointName.leftWrist.rawValue.rawValue]
    }

    /// Joints for skeleton drawing
    nonisolated static let skeletonConnections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        // Head
        (.nose, .neck),
        (.leftEye, .nose),
        (.rightEye, .nose),
        (.leftEar, .leftEye),
        (.rightEar, .rightEye),
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
        (.rightKnee, .rightAnkle)
    ]
}

/// Real-time pose detector for camera frames
final class LivePoseDetector: @unchecked Sendable {

    // MARK: - Configuration

    private let minConfidence: Float = 0.3
    private let processEveryNthFrame: Int

    // MARK: - State

    private let lock = NSLock()
    private var frameCount = 0
    private var lastPose: BodyPose?
    private let poseRequest = VNDetectHumanBodyPoseRequest()

    // MARK: - Key joints to track

    private let keyJoints: [VNHumanBodyPoseObservation.JointName] = [
        .nose,
        .neck,
        .leftEye,
        .rightEye,
        .leftEar,
        .rightEar,
        .leftShoulder,
        .rightShoulder,
        .leftElbow,
        .rightElbow,
        .leftWrist,
        .rightWrist,
        .leftHip,
        .rightHip,
        .leftKnee,
        .rightKnee,
        .leftAnkle,
        .rightAnkle
    ]

    // MARK: - Init

    /// Initialize with frame skip rate
    /// - Parameter processEveryNthFrame: Process every Nth frame (1 = all frames, 2 = every other, etc.)
    init(processEveryNthFrame: Int = 2) {
        self.processEveryNthFrame = max(1, processEveryNthFrame)
    }

    // MARK: - Detection

    /// Process a video frame and detect pose
    /// - Parameters:
    ///   - pixelBuffer: The video frame
    ///   - timestamp: Frame timestamp
    /// - Returns: Detected pose or nil
    func detectPose(in pixelBuffer: CVPixelBuffer, at timestamp: CMTime) -> BodyPose? {
        lock.lock()
        frameCount += 1
        let currentFrame = frameCount
        let shouldProcess = currentFrame % processEveryNthFrame == 0
        let cached = lastPose
        lock.unlock()

        // Skip frames for performance
        guard shouldProcess else {
            return cached
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([poseRequest])

            guard let observation = poseRequest.results?.first else {
                return nil
            }

            let pose = extractPose(from: observation, timestamp: timestamp.seconds)

            lock.lock()
            lastPose = pose
            lock.unlock()

            return pose
        } catch {
            return nil
        }
    }

    /// Get the last detected pose
    func getLastPose() -> BodyPose? {
        lock.lock()
        defer { lock.unlock() }
        return lastPose
    }

    /// Reset state
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        frameCount = 0
        lastPose = nil
    }

    // MARK: - Private

    private func extractPose(from observation: VNHumanBodyPoseObservation, timestamp: TimeInterval) -> BodyPose? {
        var joints: [String: CGPoint] = [:]
        var totalConfidence: Float = 0
        var jointCount: Float = 0

        for jointName in keyJoints {
            guard let point = try? observation.recognizedPoint(jointName),
                  point.confidence > minConfidence else {
                continue
            }

            // Store using string key for Sendable compliance
            joints[jointName.rawValue.rawValue] = point.location
            totalConfidence += point.confidence
            jointCount += 1
        }

        // Require at least some joints detected
        guard jointCount >= 4 else {
            return nil
        }

        let avgConfidence = totalConfidence / jointCount

        return BodyPose(
            timestamp: timestamp,
            joints: joints,
            confidence: avgConfidence
        )
    }
}
