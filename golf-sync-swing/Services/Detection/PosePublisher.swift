//
//  PosePublisher.swift
//  golf-sync-swing
//
//  Thread-safe bridge between background pose detection and main thread UI.
//  Stores the latest BodyJointMap for consumption by SkeletonOverlayView.
//

import Foundation

final class PosePublisher: @unchecked Sendable {

    private let lock = NSLock()
    private var _latestJointMap: BodyJointMap?

    var latestJointMap: BodyJointMap? {
        lock.lock()
        defer { lock.unlock() }
        return _latestJointMap
    }

    func publish(_ jointMap: BodyJointMap?) {
        lock.lock()
        defer { lock.unlock() }
        _latestJointMap = jointMap
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        _latestJointMap = nil
    }
}
