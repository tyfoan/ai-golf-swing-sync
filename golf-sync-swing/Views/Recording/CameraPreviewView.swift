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
    /// Bumped by `CameraService` after each (re)configuration. Passed as data rather than
    /// used as a SwiftUI `.id(...)`: identity-keying destroyed and recreated the preview
    /// view mid-bring-up, and every `previewLayer.session` (re)attach on the main thread
    /// serializes against the session queue — the first-cold-launch freeze.
    var configurationId: Int = 0
    var rotationSubjectProvider: ((AVCaptureVideoPreviewLayer) -> CaptureRotationSubject?)?
    /// Runs the dismantle-time `previewLayer.session = nil`. Detaching takes the session's
    /// internal lock — held by `startRunning` for its full duration — so doing it inline on
    /// the main thread stalled dismissal against an in-flight cold-start bring-up. The
    /// default sequences the detach behind `CameraService`'s session queue instead.
    var sessionDetacher: (AVCaptureVideoPreviewLayer) -> Void = { CameraService.shared.detachPreviewLayer($0) }
    /// Attach counterpart: `previewLayer.session = session` on a RUNNING session mutates the
    /// capture graph, and the PiP mounts exactly when recording starts — inline it raced the
    /// movie-output bootstrap on the session queue (whole preview went black on device).
    var sessionAttacher: (AVCaptureVideoPreviewLayer, AVCaptureSession) -> Void = { CameraService.shared.attachPreviewLayer($0, session: $1) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.rotationSubjectProvider = rotationSubjectProvider
        view.sessionDetacher = sessionDetacher
        view.sessionAttacher = sessionAttacher
        // Attach unconditionally. Gating this on "is the session running yet" left the layer
        // with NO session for the whole cold bring-up — a genuinely empty layer, which is
        // exactly the black capture screen reported on device. The attach itself is already
        // non-blocking (sessionQueue → main hop inside `attachPreviewLayer`), so there is
        // nothing to defend against by waiting.
        view.configureSession(session)
        view.noteConfigurationId(configurationId)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.rotationSubjectProvider = rotationSubjectProvider
        uiView.sessionDetacher = sessionDetacher
        uiView.sessionAttacher = sessionAttacher
        uiView.configureSession(session)
        uiView.noteConfigurationId(configurationId)
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        uiView.cleanup()
    }
}

class PreviewView: UIView {
    private var sessionObserver: NSKeyValueObservation?
    private var isConfigured = false
    private var rotationSubject: CaptureRotationSubject?
    private var lastConfigurationId: Int?
    private var isDetachScheduled = false
    /// The session an attach has been requested for. The attach itself is deferred through
    /// `sessionAttacher`, so `previewLayer.session` stays nil for a beat — without this,
    /// every SwiftUI update in that window would re-request the attach and re-create the KVO.
    private var attachRequestedFor: ObjectIdentifier?

    var rotationSubjectProvider: ((AVCaptureVideoPreviewLayer) -> CaptureRotationSubject?)?
    var sessionDetacher: ((AVCaptureVideoPreviewLayer) -> Void)?
    var sessionAttacher: ((AVCaptureVideoPreviewLayer, AVCaptureSession) -> Void)?

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
        guard attachRequestedFor != ObjectIdentifier(session) else { return }
        attachRequestedFor = ObjectIdentifier(session)

        sessionObserver?.invalidate()
        sessionObserver = nil
        rotationSubject = nil

        previewLayer.videoGravity = .resizeAspectFill
        // Deferred: attaching to a running session mutates the capture graph, so it must be
        // ordered behind in-flight sessionQueue work (see `sessionAttacher`).
        if let sessionAttacher {
            sessionAttacher(previewLayer, session)
        } else {
            previewLayer.session = session
        }

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

    /// A bumped id means the session was reconfigured (e.g. camera switch), so the rotation
    /// subject's captured device is stale. Only the subject is dropped here — no session
    /// state is touched, because reading the session mid-configuration from the main thread
    /// is what froze first launches. The `isRunning` KVO re-applies rotation once the
    /// reconfigured session is running again.
    func noteConfigurationId(_ id: Int) {
        guard let previous = lastConfigurationId else {
            lastConfigurationId = id
            return
        }
        guard previous != id else { return }
        lastConfigurationId = id
        rotationSubject = nil
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
        detachSession()
        isConfigured = false
        attachRequestedFor = nil
    }

    /// Hands the detach to `sessionDetacher` (which retains the layer and defers the
    /// `session = nil` until the session queue is idle) rather than assigning inline —
    /// the inline assignment blocked the main thread on the session lock during an
    /// in-flight bring-up. The flag keeps `deinit`'s second `cleanup()` from falling
    /// back to the blocking inline detach while the deferred one is still pending.
    private func detachSession() {
        guard !isDetachScheduled else { return }
        isDetachScheduled = true
        guard let sessionDetacher else {
            previewLayer.session = nil
            return
        }
        sessionDetacher(previewLayer)
    }

    deinit {
        cleanup()
    }
}

#Preview {
    CameraPreviewView(session: AVCaptureSession())
        .ignoresSafeArea()
}
