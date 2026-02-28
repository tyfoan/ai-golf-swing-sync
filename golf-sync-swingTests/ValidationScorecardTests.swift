//
//  ValidationScorecardTests.swift
//  golf-sync-swingTests
//
//  Golden-snapshot serialization support for PoseFrame data.
//  Enables validation testing on the simulator without a physical device.
//

import Testing
import Foundation
import Vision
@testable import golf_sync_swing

extension Tag {
    @Tag static var validation: Self
}

struct ValidationScorecardTests {

    @Test("JointPosition round-trips through JSON", .tags(.validation))
    func jointPositionCodable() throws {
        let original = PoseFrame.JointPosition(x: 0.42, y: 0.87, confidence: 0.95)
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PoseFrame.JointPosition.self, from: data)

        #expect(decoded.x == original.x)
        #expect(decoded.y == original.y)
        #expect(decoded.confidence == original.confidence)
    }

    @Test("PoseFrame round-trips through SerializablePoseFrame JSON", .tags(.validation))
    func poseFrameRoundTrip() throws {
        let joints: [VNHumanBodyPoseObservation.JointName: PoseFrame.JointPosition] = [
            .leftWrist: PoseFrame.JointPosition(x: 0.3, y: 0.6, confidence: 0.9),
            .rightWrist: PoseFrame.JointPosition(x: 0.7, y: 0.4, confidence: 0.85),
            .neck: PoseFrame.JointPosition(x: 0.5, y: 0.8, confidence: 0.95),
            .leftHip: PoseFrame.JointPosition(x: 0.35, y: 0.45, confidence: 0.88),
            .rightHip: PoseFrame.JointPosition(x: 0.65, y: 0.44, confidence: 0.87)
        ]
        let original = PoseFrame(
            timestamp: 1.234,
            joints: joints,
            observation: nil
        )

        let serializable = SerializablePoseFrame(poseFrame: original)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(serializable)

        let decoder = JSONDecoder()
        let restored = try decoder.decode(SerializablePoseFrame.self, from: data)
        let roundTripped = restored.toPoseFrame()

        #expect(roundTripped.timestamp == original.timestamp)
        #expect(roundTripped.observation == nil)
        #expect(roundTripped.joints.count == original.joints.count)

        for (jointName, originalPosition) in original.joints {
            let restoredPosition = roundTripped.joints[jointName]
            #expect(restoredPosition != nil, "Missing joint: \(jointName.rawValue.rawValue)")
            #expect(restoredPosition?.x == originalPosition.x)
            #expect(restoredPosition?.y == originalPosition.y)
            #expect(restoredPosition?.confidence == originalPosition.confidence)
        }
    }
}

// MARK: - Serialization Bridge

struct SerializablePoseFrame: Codable {
    let timestamp: TimeInterval
    let joints: [String: PoseFrame.JointPosition]

    init(poseFrame: PoseFrame) {
        self.timestamp = poseFrame.timestamp
        self.joints = Dictionary(
            uniqueKeysWithValues: poseFrame.joints.map { jointName, position in
                (jointName.rawValue.rawValue, position)
            }
        )
    }

    func toPoseFrame() -> PoseFrame {
        let visionJoints = Dictionary(
            uniqueKeysWithValues: joints.map { key, position in
                let jointName = VNHumanBodyPoseObservation.JointName(
                    rawValue: VNRecognizedPointKey(rawValue: key)
                )
                return (jointName, position)
            }
        )
        return PoseFrame(
            timestamp: timestamp,
            joints: visionJoints,
            observation: nil
        )
    }
}
