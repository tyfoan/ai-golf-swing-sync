//
//  SwingClassifierTests.swift
//  golf-sync-swingTests
//

import Testing
import Vision
@testable import golf_sync_swing

struct SwingClassifierTests {

    @Test("Model loads from bundle")
    func modelLoadsFromBundle() {
        let classifier = SwingClassifier()
        #expect(classifier.isAvailable)
    }

    @Test("Returns noSwing when too few frames")
    func tooFewFramesReturnsNoSwing() {
        let classifier = SwingClassifier()
        let frames = makeFrames(count: 5)
        let result = classifier.analyze(frames: frames)

        switch result {
        case .noSwing: break
        case .swingDetected: Issue.record("Should not detect swing from too few frames")
        }
    }

    @Test("Classifies static pose frames as not_swing")
    func staticPoseIsNotSwing() {
        let classifier = SwingClassifier()
        guard classifier.isAvailable else { return }

        // Static frames with no observation (zero-padded) should classify as not_swing
        let frames = makeFrames(count: 15)
        let result = classifier.analyze(frames: frames)

        switch result {
        case .noSwing: break
        case .swingDetected: Issue.record("Static zero-padded frames should not be a swing")
        }
    }

    // MARK: - Helpers

    private func makeFrames(count: Int) -> [PoseFrame] {
        (0..<count).map { i in
            PoseFrame(
                timestamp: TimeInterval(i) * 0.033,
                joints: [
                    .leftWrist: PoseFrame.JointPosition(x: 0.5, y: 0.5, confidence: 0.9)
                ]
            )
        }
    }
}
