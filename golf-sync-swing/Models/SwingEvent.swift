//
//  SwingEvent.swift
//  golf-sync-swing
//
//  Events emitted by detection strategies (SwingClassifier, PoseHeuristics).
//  Consumed by SwingStateMachine.
//

import Foundation

enum SwingEvent: Sendable {
    case swingDetected(confidence: Double, timestamp: TimeInterval)
    case noSwing
}
