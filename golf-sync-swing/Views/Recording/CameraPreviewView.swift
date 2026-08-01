//
//  CameraPreviewView.swift
//  golf-sync-swing
//
//  UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer.
//
//  This view owns NO capture-graph state and performs no capture-graph writes of its own.
//  Attaching a session, detaching it, and configuring the layer's connection all take the
//  capture session's internal lock, so all three are handed to `CameraService`, which orders
//  them against its session queue through `CaptureGraphGate`. What is left here is a layer, its
//  frame, and the two signals worth re-asking on: the session starting, and a new configuration.
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
    /// Runs the dismantle-time `previewLayer.session = nil`. Detaching takes the session's
    /// internal lock — held by `startRunning`/`stopRunning` for their full duration — so doing
    /// it inline on the main thread stalled dismissal against an in-flight bring-up, and leaving
    /// the Camera tab does both in the same turn. The default hands it to the graph gate.
    var sessionDetacher: (AVCaptureVideoPreviewLayer) -> Void = { CameraService.shared.detachPreviewLayer($0) }
    /// Attach counterpart: `previewLayer.session = session` mutates the capture graph and takes
    /// the same lock.
    var sessionAttacher: (AVCaptureVideoPreviewLayer, AVCaptureSession) -> Void = { CameraService.shared.attachPreviewLayer($0, session: $1) }
    /// Mirroring and rotation for the layer's connection. Both setters take the capture
    /// session's internal lock exactly as the attach does, so they are ordered against the
    /// session queue by the same gate rather than issued inline from a layout pass.
    var connectionConfigurator: (AVCaptureVideoPreviewLayer) -> Void = { CameraService.shared.configurePreviewConnection($0) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.sessionDetacher = sessionDetacher
        view.sessionAttacher = sessionAttacher
        view.connectionConfigurator = connectionConfigurator
        // Attach unconditionally. Gating this on "is the session running yet" left the layer
        // with NO session for the whole cold bring-up — a genuinely empty layer, which is
        // exactly the black capture screen reported on device. Waiting defends against nothing:
        // the graph gate is what decides when the assignment is safe, and on the cold path it
        // is safe immediately, because the session has not been configured or started yet.
        view.configureSession(session)
        view.noteConfigurationId(configurationId)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.sessionDetacher = sessionDetacher
        uiView.sessionAttacher = sessionAttacher
        uiView.connectionConfigurator = connectionConfigurator
        uiView.configureSession(session)
        uiView.noteConfigurationId(configurationId)
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        uiView.cleanup()
    }
}

class PreviewView: UIView {
    private var sessionObserver: NSKeyValueObservation?
    private var lastConfigurationId: Int?
    private var isDetachScheduled = false
    /// The session an attach has been requested for. The attach itself is deferred through
    /// `sessionAttacher`, so `previewLayer.session` stays nil for a beat — without this,
    /// every SwiftUI update in that window would re-request the attach and re-create the KVO.
    private var attachRequestedFor: ObjectIdentifier?

    var sessionDetacher: ((AVCaptureVideoPreviewLayer) -> Void)?
    var sessionAttacher: ((AVCaptureVideoPreviewLayer, AVCaptureSession) -> Void)?
    var connectionConfigurator: ((AVCaptureVideoPreviewLayer) -> Void)?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    /// Frame only. This used to reconfigure the connection on every pass, and connection
    /// setters take the capture session's internal lock — so a layout triggered while the
    /// session queue was mid-bring-up blocked the main thread for the rest of it. Layout is
    /// not a signal that rotation or mirroring changed; `isRunning` and the configuration id
    /// are, and both drive `configureConnection()` directly.
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    func configureSession(_ session: AVCaptureSession) {
        guard attachRequestedFor != ObjectIdentifier(session) else { return }
        attachRequestedFor = ObjectIdentifier(session)

        sessionObserver?.invalidate()
        sessionObserver = nil

        previewLayer.videoGravity = .resizeAspectFill
        // Deferred: attaching to a running session mutates the capture graph, so it must be
        // ordered behind in-flight sessionQueue work (see `sessionAttacher`).
        if let sessionAttacher {
            sessionAttacher(previewLayer, session)
        } else {
            previewLayer.session = session
        }

        // The connection does not exist until the session is both attached and configured, so
        // this first ask is usually a no-op — it covers the case of a session already running
        // when the preview mounts (returning to the tab), where no transition follows.
        configureConnection()

        sessionObserver = session.observe(\.isRunning, options: [.new, .old]) { [weak self] _, change in
            if change.oldValue == false && change.newValue == true {
                DispatchQueue.main.async {
                    self?.configureConnection()
                }
            }
        }
    }

    /// A bumped id means the session was reconfigured (e.g. camera switch), so both the
    /// mirroring and the rotation angle may have changed. No session state is read here — doing
    /// that from the main thread mid-configuration is what froze first launches; the ask is
    /// handed to the gate, which runs it once the session queue is idle.
    ///
    /// A reconfigure that does not end with the session running still gets its answer: the
    /// `isRunning` KVO fires on the restart behind it and asks again.
    func noteConfigurationId(_ id: Int) {
        guard let previous = lastConfigurationId else {
            lastConfigurationId = id
            return
        }
        guard previous != id else { return }
        lastConfigurationId = id
        configureConnection()
    }

    /// Delegated whole: mirroring and rotation are capture-graph writes, and this view is not
    /// the object that knows when the graph is free. `CameraService` owns both the gate and the
    /// rotation subject the angle comes from.
    private func configureConnection() {
        connectionConfigurator?(previewLayer)
    }

    func cleanup() {
        sessionObserver?.invalidate()
        sessionObserver = nil
        connectionConfigurator = nil
        detachSession()
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
