//
//  CameraError.swift
//  golf-sync-swing
//
//  Error types for camera capture operations.
//

import AVFoundation

enum CameraError: LocalizedError, Equatable {
    case permissionDenied
    case permissionRestricted
    case noVideoDevice
    case noAudioDevice
    case configurationFailed(String)
    case insufficientStorage
    case sessionInterrupted(InterruptionReason)
    case recordingFailed(String)

    enum InterruptionReason: Equatable {
        case audioInUse, videoInUse, backgrounded, systemPressure, unknown
    }

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera access denied. Please enable in Settings."
        case .permissionRestricted: return "Camera access is restricted on this device."
        case .noVideoDevice: return "No camera available on this device."
        case .noAudioDevice: return "No microphone available on this device."
        case .configurationFailed(let reason): return "Camera configuration failed: \(reason)"
        case .insufficientStorage: return "Not enough storage space. Please free up at least 500MB."
        case .sessionInterrupted(let reason):
            switch reason {
            case .audioInUse: return "Recording interrupted by another audio app."
            case .videoInUse: return "Camera is being used by another app."
            case .backgrounded: return "Recording paused because app went to background."
            case .systemPressure: return "Recording paused due to system resource constraints."
            case .unknown: return "Recording was interrupted."
            }
        case .recordingFailed(let reason): return "Recording failed: \(reason)"
        }
    }
}
