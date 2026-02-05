import Testing
@testable import golf_sync_swing

struct LiveSwingDetectorTests {

    @Test func detectsSwingAtVelocityPeak() async throws {
        let detector = LiveSwingDetector()
        var detected: SwingBounds?
        detector.onSwingDetected = { swing in
            detected = swing
        }

        // Simulate a fast downswing with a clear velocity peak at t=0.2s,
        // followed by deceleration for 3 frames to confirm the peak.
        let samples: [(t: TimeInterval, rightWristY: Double)] = [
            (0.0, 0.50),
            (0.1, 0.45), // v=-0.5
            (0.2, 0.35), // v=-1.0 (peak)
            (0.3, 0.28), // v=-0.7
            (0.4, 0.22), // v=-0.6
            (0.5, 0.18)  // v=-0.4 (peak confirmed)
        ]

        for s in samples {
            detector.addPose(timestamp: s.t, leftWristY: nil, rightWristY: s.rightWristY)
        }

        #expect(detected != nil)
        guard let swing = detected else { return }

        #expect(abs(swing.impactTime - 0.2) < 0.0001)
        #expect(abs(swing.detectionTime - 0.5) < 0.0001)
        #expect(swing.startTime == 0.0)
        #expect(abs(swing.endTime - 0.8) < 0.0001)
        #expect(swing.confidence >= 0.99)
        #expect(swing.audioConfirmed == false)
    }
}

