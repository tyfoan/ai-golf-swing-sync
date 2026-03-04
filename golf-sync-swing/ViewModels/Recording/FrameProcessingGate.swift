//
//  FrameProcessingGate.swift
//  golf-sync-swing
//
//  Thread-safe frame processing gate and recording timestamp tracker.
//  Prevents camera buffer pool exhaustion by dropping frames when busy.
//

import AVFoundation
import Foundation
import os

final class FrameProcessingGate: @unchecked Sendable {

    private let lock = NSLock()
    private var _isProcessingFrame = false
    private var _isCurrentlyRecording = false
    private var _recordingStartTimestamp: TimeInterval?
    private var _frameProcessedCount: Int = 0

    // MARK: - Recording State

    var isCurrentlyRecording: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isCurrentlyRecording }
        set { lock.lock(); defer { lock.unlock() }; _isCurrentlyRecording = newValue }
    }

    var recordingStartTimestamp: TimeInterval? {
        get { lock.lock(); defer { lock.unlock() }; return _recordingStartTimestamp }
        set { lock.lock(); defer { lock.unlock() }; _recordingStartTimestamp = newValue }
    }

    var frameProcessedCount: Int {
        get { lock.lock(); defer { lock.unlock() }; return _frameProcessedCount }
    }

    // MARK: - Frame Gate

    /// Try to acquire the gate. Returns false if already processing.
    func tryAcquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_isProcessingFrame else { return false }
        _isProcessingFrame = true
        return true
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        _isProcessingFrame = false
    }

    // MARK: - Frame Timing

    /// Record frame timestamp and return file-relative time.
    /// Captures first frame timestamp for offset calculation.
    func recordFrame(at cameraTime: TimeInterval) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        if _recordingStartTimestamp == nil {
            _recordingStartTimestamp = cameraTime
            AppLogger.camera.debug("RecordingVM: First frame at \(cameraTime)s")
        }
        _frameProcessedCount += 1
        let count = _frameProcessedCount
        let startTime = _recordingStartTimestamp ?? 0

        let relativeTime = cameraTime - startTime
        if count % 60 == 0 {
            AppLogger.camera.debug("RecordingVM: Processed \(count) frames, t=\(String(format: "%.2f", relativeTime))s")
        }
        return relativeTime
    }

    // MARK: - Reset

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _isProcessingFrame = false
        _isCurrentlyRecording = false
        _recordingStartTimestamp = nil
        _frameProcessedCount = 0
    }
}
