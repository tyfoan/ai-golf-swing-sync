//
//  CameraPermissionManager.swift
//  golf-sync-swing
//
//  Handles camera and microphone permission requests and state checks.
//

import AVFoundation

protocol CameraPermissionManaging: Sendable {
    func requestPermissions() async -> Bool
    func checkPermissionState() -> (video: AVAuthorizationStatus, audio: AVAuthorizationStatus)
}

final class CameraPermissionManager: CameraPermissionManaging, @unchecked Sendable {

    func requestPermissions() async -> Bool {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        var videoGranted = videoStatus == .authorized
        var audioGranted = audioStatus == .authorized

        if videoStatus == .notDetermined {
            videoGranted = await AVCaptureDevice.requestAccess(for: .video)
        }

        if audioStatus == .notDetermined {
            audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
        }

        return videoGranted && audioGranted
    }

    func checkPermissionState() -> (video: AVAuthorizationStatus, audio: AVAuthorizationStatus) {
        (
            AVCaptureDevice.authorizationStatus(for: .video),
            AVCaptureDevice.authorizationStatus(for: .audio)
        )
    }
}
