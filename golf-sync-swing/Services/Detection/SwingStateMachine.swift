//
//  SwingStateMachine.swift
//  golf-sync-swing
//
//  Manages swing detection state transitions.
//  States: idle -> swingDetected -> replayReady -> cooldown -> idle
//

import Foundation
import os

struct SwingDetection: Sendable {
    let confidence: Double
    let detectionTimestamp: TimeInterval
}

final class SwingStateMachine: @unchecked Sendable {

    enum State: Equatable, Sendable {
        case idle
        case swingDetected
        case replayReady
        case cooldown
    }

    private(set) var currentState: State = .idle
    private let cooldownDuration: TimeInterval
    private var cooldownStartTime: TimeInterval = 0
    private let lock = NSLock()

    init(cooldownDuration: TimeInterval = 2.0) {
        self.cooldownDuration = cooldownDuration
    }

    func handle(event: SwingEvent) -> SwingDetection? {
        lock.lock()
        defer { lock.unlock() }

        switch event {
        case .swingDetected(let confidence, let timestamp):
            return handleSwingDetected(confidence: confidence, timestamp: timestamp)
        case .noSwing:
            return nil
        }
    }

    func transitionToReplay(impactTime: TimeInterval, startTime: TimeInterval, endTime: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        currentState = .cooldown
        cooldownStartTime = endTime
        let cooldownEnd = endTime + self.cooldownDuration
        AppLogger.detection.info("SwingStateMachine: -> cooldown (until \(String(format: "%.1f", cooldownEnd))s)")
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        currentState = .idle
        cooldownStartTime = 0
    }

    private func handleSwingDetected(confidence: Double, timestamp: TimeInterval) -> SwingDetection? {
        switch currentState {
        case .idle:
            currentState = .swingDetected
            AppLogger.detection.info("SwingStateMachine: -> swingDetected (conf=\(String(format: "%.2f", confidence)) at \(String(format: "%.2f", timestamp))s)")
            return SwingDetection(confidence: confidence, detectionTimestamp: timestamp)

        case .cooldown:
            let elapsed = timestamp - cooldownStartTime
            guard elapsed >= cooldownDuration else { return nil }

            currentState = .swingDetected
            AppLogger.detection.info("SwingStateMachine: cooldown expired -> swingDetected")
            return SwingDetection(confidence: confidence, detectionTimestamp: timestamp)

        case .swingDetected, .replayReady:
            return nil
        }
    }
}
