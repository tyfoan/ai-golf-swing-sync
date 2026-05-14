//
//  CameraPreviewView.swift
//  golf-sync-swing
//
//  UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer.
//  Each instance owns its own preview-side rotation via a CaptureRotationSubject
//  built by the caller (typically CameraService.makePreviewRotationSubject(for:)).
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var rotationSubjectProvider: ((AVCaptureVideoPreviewLayer) -> CaptureRotationSubject?)?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.rotationSubjectProvider = rotationSubjectProvider
        view.configureSession(session)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.rotationSubjectProvider = rotationSubjectProvider
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
    private var rotationSubject: CaptureRotationSubject?

    var rotationSubjectProvider: ((AVCaptureVideoPreviewLayer) -> CaptureRotationSubject?)?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds

        if bounds.size != .zero && isConfigured {
            configureConnection()
        }
    }

    func configureSession(_ session: AVCaptureSession) {
        sessionObserver?.invalidate()
        sessionObserver = nil
        rotationSubject = nil

        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill

        isConfigured = true

        DispatchQueue.main.async { [weak self] in
            self?.configureConnection()
        }

        sessionObserver = session.observe(\.isRunning, options: [.new, .old]) { [weak self] _, change in
            if change.oldValue == false && change.newValue == true {
                DispatchQueue.main.async {
                    self?.configureConnection()
                }
            }
        }
    }

    private func configureConnection() {
        guard let connection = previewLayer.connection else { return }

        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = true
        }

        applyRotation()
    }

    private func applyRotation() {
        if rotationSubject == nil {
            rotationSubject = rotationSubjectProvider?(previewLayer)
        }
        rotationSubject?.applyPreviewAngle()
    }

    func cleanup() {
        sessionObserver?.invalidate()
        sessionObserver = nil
        rotationSubject = nil
        rotationSubjectProvider = nil
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
