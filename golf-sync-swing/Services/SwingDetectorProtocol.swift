//
//  SwingDetectorProtocol.swift
//  golf-sync-swing
//
//  Common protocol for real-time swing detection
//

import AVFoundation

/// Protocol for real-time swing detection during recording
/// All methods are nonisolated to allow calling from background threads
protocol RealTimeSwingDetector: AnyObject, Sendable {

    /// Called when a complete swing is detected
    var onSwingDetected: (@Sendable (SwingBounds) -> Void)? { get set }

    /// Called when the current phase changes (for UI feedback)
    var onPhaseChanged: ((_ phase: String, _ confidence: Double) -> Void)? { get set }

    /// Whether the detector is currently tracking a swing
    nonisolated var isTrackingSwing: Bool { get }

    /// Whether motion is currently detected (for UI feedback, e.g. activity indicator)
    nonisolated var isMotionDetected: Bool { get }

    /// Process a video frame for swing detection (called from background thread)
    nonisolated func processFrame(_ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval)

    /// Reset detector state
    nonisolated func reset()
}

// MARK: - Protocol Conformance

extension SwingNetDetector: RealTimeSwingDetector {}
