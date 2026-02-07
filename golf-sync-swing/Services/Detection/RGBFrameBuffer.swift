//
//  RGBFrameBuffer.swift
//  golf-sync-swing
//
//  Thread-safe ring buffer for raw RGB frame data.
//  Stores ContiguousArray<UInt8> pixel data with timestamps
//  for SwingNet's sliding window input.
//

import Foundation

struct RGBFrameData {
    let timestamp: TimeInterval
    let rgbData: ContiguousArray<UInt8>  // Raw 0-255 RGB data (3 * 160 * 160)
}

final class RGBFrameBuffer: @unchecked Sendable {

    private let lock = NSLock()
    private var frames: ContiguousArray<RGBFrameData> = []
    private let capacity: Int

    init(capacity: Int = 64) {
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

    func append(_ frame: RGBFrameData) {
        lock.lock()
        defer { lock.unlock() }
        frames.append(frame)
        while frames.count > capacity {
            frames.removeFirst()
        }
    }

    func snapshot(last n: Int? = nil) -> [RGBFrameData] {
        lock.lock()
        defer { lock.unlock() }
        if let n {
            return Array(frames.suffix(n))
        }
        return Array(frames)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        frames.removeAll()
    }
}
