//
//  PoseHeuristicsTests.swift
//  golf-sync-swingTests
//

import Testing
import Vision
@testable import golf_sync_swing

struct PoseHeuristicsTests {

    @Test("Detects swing from high wrist velocity")
    func detectsSwingFromWristVelocity() {
        let heuristics = PoseHeuristics()

        var frames: [PoseFrame] = []
        for i in 0..<15 {
            let y: CGFloat
            if i < 5 {
                y = 0.7
            } else if i < 11 {
                y = 0.7 - CGFloat(i - 5) * 0.08
            } else {
                y = 0.25 + CGFloat(i - 11) * 0.05
            }

            let wrist = PoseFrame.JointPosition(x: 0.5, y: y, confidence: 0.8)
            let hip = PoseFrame.JointPosition(x: 0.5, y: 0.55, confidence: 0.9)
            frames.append(PoseFrame(
                timestamp: TimeInterval(i) * 0.033,
                joints: [.leftWrist: wrist, .leftHip: hip, .rightHip: hip]
            ))
        }

        let event = heuristics.analyze(frames: frames)

        switch event {
        case .swingDetected: break
        case .noSwing: Issue.record("Expected swing detection")
        }
    }

    @Test("Does not detect swing from slow movement")
    func noDetectionFromSlowMovement() {
        let heuristics = PoseHeuristics()

        let frames = (0..<15).map { i -> PoseFrame in
            let y = 0.5 + CGFloat(i) * 0.01
            let wrist = PoseFrame.JointPosition(x: 0.5, y: y, confidence: 0.8)
            let hip = PoseFrame.JointPosition(x: 0.5, y: 0.55, confidence: 0.9)
            return PoseFrame(
                timestamp: TimeInterval(i) * 0.033,
                joints: [.leftWrist: wrist, .leftHip: hip, .rightHip: hip]
            )
        }

        let event = heuristics.analyze(frames: frames)

        switch event {
        case .swingDetected: Issue.record("Should not detect slow movement as swing")
        case .noSwing: break
        }
    }
}
