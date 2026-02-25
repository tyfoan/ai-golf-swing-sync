//
//  ImpactDetectorTests.swift
//  golf-sync-swingTests
//

import Testing
import Vision
@testable import golf_sync_swing

struct ImpactDetectorTests {

    @Test("Finds frame with lowest wrist y-position")
    func findsLowestWristY() {
        let detector = ImpactDetector()

        let frames = (0..<10).map { i -> PoseFrame in
            let y = abs(CGFloat(i) - 5.0) * 0.1 + 0.2
            let wrist = PoseFrame.JointPosition(x: 0.5, y: y, confidence: 0.8)
            return PoseFrame(
                timestamp: TimeInterval(i) * 0.033,
                joints: [.leftWrist: wrist]
            )
        }

        let impactTime = detector.findImpactTime(in: frames)
        let expectedTime = 5.0 * 0.033

        #expect(impactTime != nil)
        #expect(abs(impactTime! - expectedTime) < 0.001)
    }

    @Test("Returns nil when no wrist data available")
    func noWristData() {
        let detector = ImpactDetector()
        let frames = (0..<5).map { i in
            PoseFrame(timestamp: TimeInterval(i) * 0.033, joints: [:])
        }
        let impactTime = detector.findImpactTime(in: frames)
        #expect(impactTime == nil)
    }

    @Test("Picks lower wrist for handedness detection")
    func picksLowerWrist() {
        let detector = ImpactDetector()
        let leftWrist = PoseFrame.JointPosition(x: 0.3, y: 0.4, confidence: 0.8)
        let rightWrist = PoseFrame.JointPosition(x: 0.7, y: 0.2, confidence: 0.8)
        let frame = PoseFrame(
            timestamp: 1.0,
            joints: [.leftWrist: leftWrist, .rightWrist: rightWrist]
        )
        let impactTime = detector.findImpactTime(in: [frame])
        #expect(impactTime == 1.0)
    }
}
