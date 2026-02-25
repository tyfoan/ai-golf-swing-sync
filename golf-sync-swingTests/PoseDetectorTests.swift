//
//  PoseDetectorTests.swift
//  golf-sync-swingTests
//

import Testing
import Vision
@testable import golf_sync_swing

struct PoseDetectorTests {

    @Test("Ring buffer maintains correct size")
    func ringBufferSize() {
        let detector = PoseDetector(bufferCapacity: 5)
        let emptyFrame = PoseFrame(timestamp: 0, joints: [:])

        for _ in 0..<10 {
            detector.appendToBuffer(emptyFrame)
        }

        #expect(detector.bufferCount == 5)
    }

    @Test("Ring buffer returns frames in chronological order")
    func ringBufferOrder() {
        let detector = PoseDetector(bufferCapacity: 3)

        for i in 0..<5 {
            let frame = PoseFrame(timestamp: TimeInterval(i), joints: [:])
            detector.appendToBuffer(frame)
        }

        let frames = detector.recentFrames(count: 3)
        #expect(frames.count == 3)
        #expect(frames[0].timestamp == 2.0)
        #expect(frames[1].timestamp == 3.0)
        #expect(frames[2].timestamp == 4.0)
    }

    @Test("Extract pose from static image produces frame with timestamp")
    func extractPoseFromImage() throws {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 160, 160, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        guard let buffer = pixelBuffer else {
            Issue.record("Failed to create pixel buffer")
            return
        }

        let detector = PoseDetector()
        let frame = detector.extractPose(from: buffer, at: 0.5)

        #expect(frame.timestamp == 0.5)
    }
}
