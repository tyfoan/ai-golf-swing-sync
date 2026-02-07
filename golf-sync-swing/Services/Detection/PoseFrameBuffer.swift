//
//  PoseFrameBuffer.swift
//  golf-sync-swing
//
//  Thread-safe ring buffer for pose keypoint frames.
//  Stores MLMultiArray keypoints with timestamps for sliding window classification.
//

import CoreML
import Foundation

struct PoseFrame {
    let timestamp: TimeInterval
    let keypointsArray: MLMultiArray  // Shape: (3, 18)
}

final class PoseFrameBuffer: @unchecked Sendable {

    private let lock = NSLock()
    private var frames: [PoseFrame] = []
    private let capacity: Int

    init(capacity: Int = 60) {
        self.capacity = capacity
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames.count
    }

    var isFull: Bool {
        lock.lock()
        defer { lock.unlock() }
        return frames.count >= capacity
    }

    func append(_ frame: PoseFrame) {
        lock.lock()
        defer { lock.unlock() }
        frames.append(frame)
        while frames.count > capacity {
            frames.removeFirst()
        }
    }

    func snapshot(last n: Int? = nil) -> [PoseFrame] {
        lock.lock()
        defer { lock.unlock() }
        if let n {
            return Array(frames.suffix(n))
        }
        return frames
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        frames.removeAll()
    }
}
