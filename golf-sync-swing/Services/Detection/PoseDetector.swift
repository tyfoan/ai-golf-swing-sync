//
//  PoseDetector.swift
//  golf-sync-swing
//
//  Extracts body pose from camera frames using VNSequenceRequestHandler
//  and maintains a ring buffer of recent PoseFrames.
//
//  VNSequenceRequestHandler provides temporal smoothing between frames,
//  reducing joint position jitter during fast motion (downswing).
//

import CoreVideo
import Vision
import os

final class PoseDetector: @unchecked Sendable {

    private let sequenceHandler = VNSequenceRequestHandler()
    private let bufferCapacity: Int
    private var buffer: [PoseFrame]
    private var writeIndex: Int = 0
    private var totalWritten: Int = 0
    private let lock = NSLock()
    private let minimumConfidence: Float = 0.1

    init(bufferCapacity: Int = 90) {
        self.bufferCapacity = bufferCapacity
        self.buffer = []
        self.buffer.reserveCapacity(bufferCapacity)
    }

    // MARK: - Pose Extraction

    func extractPose(from pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) -> PoseFrame {
        let request = VNDetectHumanBodyPoseRequest()

        do {
            try sequenceHandler.perform([request], on: pixelBuffer)
        } catch {
            AppLogger.detection.debug("Pose extraction failed: \(error.localizedDescription)")
            return PoseFrame(timestamp: timestamp, joints: [:])
        }

        guard let observation = request.results?.first else {
            return PoseFrame(timestamp: timestamp, joints: [:])
        }

        let joints = extractJoints(from: observation)
        return PoseFrame(timestamp: timestamp, joints: joints, observation: observation)
    }

    func processFrame(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> PoseFrame {
        let frame = extractPose(from: pixelBuffer, at: timestamp)
        appendToBuffer(frame)
        return frame
    }

    // MARK: - Ring Buffer

    func appendToBuffer(_ frame: PoseFrame) {
        lock.lock()
        defer { lock.unlock() }

        if buffer.count < bufferCapacity {
            buffer.append(frame)
        } else {
            buffer[writeIndex] = frame
        }

        writeIndex = (writeIndex + 1) % bufferCapacity
        totalWritten += 1
    }

    var bufferCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    func recentFrames(count: Int) -> [PoseFrame] {
        lock.lock()
        defer { lock.unlock() }

        let available = min(count, buffer.count)
        guard available > 0 else { return [] }

        var result: [PoseFrame] = []
        result.reserveCapacity(available)

        let startOffset = buffer.count < bufferCapacity
            ? max(0, buffer.count - available)
            : (writeIndex - available + bufferCapacity) % bufferCapacity

        for i in 0..<available {
            let index = buffer.count < bufferCapacity
                ? startOffset + i
                : (startOffset + i) % bufferCapacity
            result.append(buffer[index])
        }

        return result
    }

    func clearBuffer() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
        writeIndex = 0
        totalWritten = 0
    }

    // MARK: - Joint Extraction

    private static let trackedJoints: [VNHumanBodyPoseObservation.JointName] = [
        .leftWrist, .rightWrist,
        .leftShoulder, .rightShoulder,
        .leftHip, .rightHip,
        .leftElbow, .rightElbow,
        .neck,
        .leftAnkle, .rightAnkle
    ]

    private func extractJoints(
        from observation: VNHumanBodyPoseObservation
    ) -> [VNHumanBodyPoseObservation.JointName: PoseFrame.JointPosition] {
        var joints: [VNHumanBodyPoseObservation.JointName: PoseFrame.JointPosition] = [:]

        for jointName in Self.trackedJoints {
            guard let point = try? observation.recognizedPoint(jointName),
                  point.confidence > minimumConfidence else {
                continue
            }

            joints[jointName] = PoseFrame.JointPosition(
                x: point.location.x,
                y: point.location.y,
                confidence: point.confidence
            )
        }

        return joints
    }
}
