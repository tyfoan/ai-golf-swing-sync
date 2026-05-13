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
        case .permissionDenied:
            return String(localized: "Camera access denied. Please enable in Settings.", comment: "CameraError: user has denied camera permission in iOS Settings")
        case .permissionRestricted:
            return String(localized: "Camera access is restricted on this device.", comment: "CameraError: camera is disabled by parental controls or MDM")
        case .noVideoDevice:
            return String(localized: "No camera available on this device.", comment: "CameraError: hardware has no camera (rare — simulator or stripped device)")
        case .noAudioDevice:
            return String(localized: "No microphone available on this device.", comment: "CameraError: hardware has no microphone")
        case .configurationFailed(let reason):
            return String(localized: "Camera configuration failed: \(reason)", comment: "CameraError: AVCaptureSession configuration failed — placeholder is the underlying reason")
        case .insufficientStorage:
            return String(localized: "Not enough storage space. Please free up at least 500MB.", comment: "CameraError: device free space below the threshold needed to record")
        case .sessionInterrupted(let reason):
            switch reason {
            case .audioInUse:
                return String(localized: "Recording interrupted by another audio app.", comment: "CameraError: another app is using audio (e.g. phone call, voice memo)")
            case .videoInUse:
                return String(localized: "Camera is being used by another app.", comment: "CameraError: another app holds the camera (rare on iOS)")
            case .backgrounded:
                return String(localized: "Recording paused because app went to background.", comment: "CameraError: user backgrounded the app mid-recording")
            case .systemPressure:
                return String(localized: "Recording paused due to system resource constraints.", comment: "CameraError: AVCaptureSessionInterruptionReasonSystemPressure (thermal or resource throttling)")
            case .unknown:
                return String(localized: "Recording was interrupted.", comment: "CameraError: unspecified session interruption")
            }
        case .recordingFailed(let reason):
            return String(localized: "Recording failed: \(reason)", comment: "CameraError: AVCaptureMovieFileOutput failed — placeholder is the underlying reason")
        }
    }
}
