//
//  LivePoseDetector.swift
//  golf-sync-swing
//
//  Real-time body pose detection using Vision framework
//  Optimized for fast swing detection with adaptive frame processing
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

    /// Get left wrist position
    nonisolated var leftWristPosition: CGPoint? {
        joints[VNHumanBodyPoseObservation.JointName.leftWrist.rawValue.rawValue]
    }

    /// Get right wrist position
    nonisolated var rightWristPosition: CGPoint? {
        joints[VNHumanBodyPoseObservation.JointName.rightWrist.rawValue.rawValue]
    }

    /// Get wrist position (prefers right wrist) - legacy compatibility
    nonisolated var wristPosition: CGPoint? {
        rightWristPosition ?? leftWristPosition
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
/// Supports adaptive frame processing for battery efficiency
final class LivePoseDetector: @unchecked Sendable {

    // MARK: - Configuration

    private let minConfidence: Float = 0.3

    /// Base frame skip rate (when not actively tracking)
    private let baseFrameSkip: Int

    /// Frame skip rate during active tracking (process every frame)
    private let activeFrameSkip: Int = 1

    // MARK: - State

    private let lock = NSLock()
    private var frameCount = 0
    private var lastPose: BodyPose?
    private let poseRequest = VNDetectHumanBodyPoseRequest()

    /// When true, processes every frame (used during active swing tracking)
    private var isActiveTracking = false

    // MARK: - Key joints to track (optimized set for swing detection)

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
    /// - Parameter processEveryNthFrame: Process every Nth frame when idle (1 = all frames, 2 = every other, etc.)
    init(processEveryNthFrame: Int = 2) {
        self.baseFrameSkip = max(1, processEveryNthFrame)
    }

    // MARK: - Adaptive Processing Control

    /// Enable active tracking mode (process every frame)
    func setActiveTracking(_ active: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isActiveTracking = active
    }

    /// Check if active tracking is enabled
    func getActiveTracking() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isActiveTracking
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
        let frameSkip = isActiveTracking ? activeFrameSkip : baseFrameSkip
        let shouldProcess = currentFrame % frameSkip == 0
        let cached = lastPose
        lock.unlock()

        // Skip frames for performance (unless active tracking)
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
        isActiveTracking = false
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
