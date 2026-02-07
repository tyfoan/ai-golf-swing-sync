//
//  CameraNotificationHandler.swift
//  golf-sync-swing
//
//  Handles AVCaptureSession notifications: interruption, resume, runtime errors.
//

import AVFoundation

final class CameraNotificationHandler: NSObject {

    var onInterrupted: ((CameraError.InterruptionReason) -> Void)?
    var onInterruptionEnded: (() -> Void)?
    var onRuntimeError: ((AVError) -> Void)?

    func register(for session: AVCaptureSession) {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        nc.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
        nc.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: session)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        let reason = parseInterruptionReason(from: notification)
        onInterrupted?(reason)
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        onInterruptionEnded?()
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        onRuntimeError?(error)
    }

    private func parseInterruptionReason(from notification: Notification) -> CameraError.InterruptionReason {
        guard let rawReason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
              let interruptionReason = AVCaptureSession.InterruptionReason(rawValue: rawReason) else {
            return .unknown
        }
        switch interruptionReason {
        case .videoDeviceNotAvailableInBackground: return .backgrounded
        case .audioDeviceInUseByAnotherClient: return .audioInUse
        case .videoDeviceInUseByAnotherClient, .videoDeviceNotAvailableWithMultipleForegroundApps: return .videoInUse
        case .videoDeviceNotAvailableDueToSystemPressure: return .systemPressure
        default: return .unknown
        }
    }
}
