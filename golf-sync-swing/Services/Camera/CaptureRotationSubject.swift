//
//  CaptureRotationSubject.swift
//  golf-sync-swing
//
//  Wraps AVCaptureDevice.RotationCoordinator to apply the device-correct
//  rotation angle to preview + capture connections. Replaces the legacy
//  hardcoded `videoRotationAngle = 90`, which assumed a landscape-left sensor
//  natural orientation — true for iPhone 16 and earlier, false for the iPhone
//  17 family's new front camera.
//
//  Behavior: one-shot. We read the coordinator's angles at registration time
//  and apply them; we do NOT observe orientation changes. The app is
//  portrait-locked, so we treat the angle the coordinator reports while the
//  phone is portrait as the canonical recording rotation.
//

import AVFoundation
import UIKit

final class CaptureRotationSubject {

    private let coordinator: AVCaptureDevice.RotationCoordinator
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureConnections: [AVCaptureConnection] = []

    init(device: AVCaptureDevice, previewLayer: AVCaptureVideoPreviewLayer?) {
        self.coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        self.previewLayer = previewLayer
    }

    func register(captureConnection: AVCaptureConnection?) {
        guard let connection = captureConnection else { return }
        captureConnections.append(connection)
        apply(angle: coordinator.videoRotationAngleForHorizonLevelCapture, to: connection)
    }

    func applyPreviewAngle() {
        guard let connection = previewLayer?.connection else { return }
        apply(angle: coordinator.videoRotationAngleForHorizonLevelPreview, to: connection)
    }

    func applyCaptureAngles() {
        let angle = coordinator.videoRotationAngleForHorizonLevelCapture
        captureConnections.forEach { apply(angle: angle, to: $0) }
    }

    private func apply(angle: CGFloat, to connection: AVCaptureConnection) {
        guard connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}
