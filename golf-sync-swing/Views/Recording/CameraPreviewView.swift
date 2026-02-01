//
//  CameraPreviewView.swift
//  golf-sync-swing
//
//  UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.configureSession(session)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Only reconfigure if session changed or isn't set
        if uiView.previewLayer.session !== session {
            uiView.configureSession(session)
        }
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        uiView.cleanup()
    }
}

class PreviewView: UIView {
    private var sessionObserver: NSKeyValueObservation?
    private var isConfigured = false

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds

        // Reconfigure connection after layout (frame must be non-zero)
        if bounds.size != .zero && isConfigured {
            configureConnection()
        }
    }

    func configureSession(_ session: AVCaptureSession) {
        // Remove old observer
        sessionObserver?.invalidate()
        sessionObserver = nil

        // Set session - this creates the connection
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill

        isConfigured = true

        // Configure connection after a brief delay to let session stabilize
        DispatchQueue.main.async { [weak self] in
            self?.configureConnection()
        }

        // Also observe session running state
        sessionObserver = session.observe(\.isRunning, options: [.new, .old]) { [weak self] session, change in
            // Only configure when session transitions to running
            if change.oldValue == false && change.newValue == true {
                DispatchQueue.main.async {
                    self?.configureConnection()
                }
            }
        }
    }

    private func configureConnection() {
        guard let connection = previewLayer.connection else {
            // No connection yet - preview layer may need time to create it
            return
        }

        // Set portrait orientation
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        // Enable mirroring for front camera (automaticallyAdjustsVideoMirroring handles this)
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = true
        }
    }

    func cleanup() {
        sessionObserver?.invalidate()
        sessionObserver = nil
        previewLayer.session = nil
        isConfigured = false
    }

    deinit {
        cleanup()
    }
}

#Preview {
    CameraPreviewView(session: AVCaptureSession())
        .ignoresSafeArea()
}
