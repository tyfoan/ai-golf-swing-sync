//
//  RecordingTypes.swift
//  golf-sync-swing
//
//  Shared types for recording workflow
//

import Foundation

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case countdown(remaining: Int)
    case recording
    case finalizingVideo
    case saving
    case saved
    case reviewing

    static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording),
             (.finalizingVideo, .finalizingVideo),
             (.saving, .saving), (.saved, .saved), (.reviewing, .reviewing): return true
        case (.countdown(let a), .countdown(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - PiP Display Mode

/// What the PiP view is showing during recording
enum PipDisplayMode: Equatable {
    case liveCamera
    case lastSwingReplay
}

// MARK: - Swing Clip

/// Detected swing clip during recording
struct SwingClip: Identifiable, Equatable {
    let id: UUID
    let startTime: TimeInterval
    let impactTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let detectionTime: TimeInterval
    let audioConfirmed: Bool
    var isFavorite: Bool = false

    init(id: UUID = UUID(), startTime: TimeInterval, impactTime: TimeInterval, endTime: TimeInterval, confidence: Double, detectionTime: TimeInterval, audioConfirmed: Bool = false, isFavorite: Bool = false) {
        self.id = id
        self.startTime = startTime
        self.impactTime = impactTime
        self.endTime = endTime
        self.confidence = confidence
        self.detectionTime = detectionTime
        self.audioConfirmed = audioConfirmed
        self.isFavorite = isFavorite
    }

}
