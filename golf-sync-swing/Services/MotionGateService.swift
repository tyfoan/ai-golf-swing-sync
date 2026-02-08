//
//  MotionGateService.swift
//  golf-sync-swing
//
//  Lightweight frame-differencing service for motion detection.
//  Compares current frame to a reference frame to classify motion state.
//  Cost: ~0.1ms per frame (subsampled R-channel comparison).
//

import Foundation

final class MotionGateService: @unchecked Sendable {

    enum MotionState {
        case idle    // No significant motion
        case active  // Moderate motion detected
        case peak    // Rapid motion (likely mid-swing)
    }

    // MARK: - Configuration

    /// How many frames between reference frame updates
    private let referenceUpdateInterval: Int = 30

    /// Subsample stride — check every Nth pixel of the R channel only
    private let subsampleStride: Int = 4

    /// Thresholds for average absolute pixel difference (0-255 scale)
    private let activeThreshold: Float = 8.0
    private let peakThreshold: Float = 20.0

    // MARK: - State

    private let lock = NSLock()

    /// Reference frame R-channel values (subsampled)
    private var referencePixels: ContiguousArray<UInt8> = []

    /// Frame counter since last reference update
    private var framesSinceReference: Int = 0

    // MARK: - Public API

    /// Update with new frame's raw RGB data (CHW layout: R plane first, then G, then B).
    /// Each plane is 160*160 = 25600 pixels. Total array size: 76800.
    /// Returns the current motion state.
    func update(with rgbData: ContiguousArray<UInt8>) -> MotionState {
        let pixelsPerChannel = 25600  // 160 * 160
        guard rgbData.count >= pixelsPerChannel else { return .idle }

        // Subsample R channel (first plane in CHW layout)
        let sampleCount = pixelsPerChannel / subsampleStride
        var currentSamples = ContiguousArray<UInt8>()
        currentSamples.reserveCapacity(sampleCount)
        for i in stride(from: 0, to: pixelsPerChannel, by: subsampleStride) {
            currentSamples.append(rgbData[i])
        }

        // First frame or after reset — store as reference
        lock.lock()
        if referencePixels.isEmpty {
            referencePixels = currentSamples
            framesSinceReference = 0
            lock.unlock()
            return .idle
        }

        // Compute average absolute difference
        var totalDiff: Int = 0
        let count = min(currentSamples.count, referencePixels.count)
        for i in 0..<count {
            let diff = Int(currentSamples[i]) - Int(referencePixels[i])
            totalDiff += abs(diff)
        }
        let avgDiff = Float(totalDiff) / Float(count)

        // Update reference periodically
        framesSinceReference += 1
        if framesSinceReference >= referenceUpdateInterval {
            referencePixels = currentSamples
            framesSinceReference = 0
        }
        lock.unlock()

        // Classify motion
        if avgDiff >= peakThreshold {
            return .peak
        } else if avgDiff >= activeThreshold {
            return .active
        } else {
            return .idle
        }
    }

    /// Reset state (e.g. when recording stops)
    func reset() {
        lock.lock()
        referencePixels.removeAll()
        framesSinceReference = 0
        lock.unlock()
    }
}
