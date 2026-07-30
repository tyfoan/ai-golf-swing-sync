//
//  CameraService.swift
//  golf-sync-swing
//
//  Facade for camera capture session management.
//  Delegates to collaborators:
//    CameraPermissionManager      - Permission requests and state checks
//    CaptureSessionConfigurator   - Session setup and format negotiation
//    RecordingCoordinator         - Recording lifecycle and duration timer
//
//  Error types: CameraError.swift
//

import AVFoundation
import Observation
import UIKit
import os

@Observable
final class CameraService: NSObject {

    // MARK: - Shared Instance

    /// Process-wide camera handle. The capture session is a process-level
    /// resource; it is brought up lazily by RecordingView when the Camera tab
    /// appears (onboarding only requests permission — no pre-warm, so the
    /// camera never runs unseen).
    static let shared = CameraService()

    // MARK: - Observable State

    var isSessionRunning = false
    var isRecording = false
    /// Mirrored from RecordingCoordinator's timer via `onDurationTick`. Stored
    /// (not computed) so SwiftUI's @Observable can track changes — the
    /// coordinator itself isn't @Observable.
    var recordedDuration: TimeInterval = 0
    var sessionConfigurationId: Int = 0
    var droppedFrameCount: Int = 0
    var currentError: CameraError?
    var isInterrupted = false

    // MARK: - Capture Session

    let captureSession = AVCaptureSession()
    private(set) var currentCameraPosition: AVCaptureDevice.Position = .back

    /// A few seconds of the take, downscaled and JPEG-encoded, so the Camera tab can replay a
    /// detected swing without a second preview layer and without reading the in-progress
    /// recording file — the two things that each broke this screen once. Armed by
    /// `startRecording()`, dropped the moment the recording ends; while idle it costs one bool
    /// read per frame.
    ///
    /// The video queue's share of it is a `memcpy` into a buffer the ring owns; the scale and
    /// the encode happen on the ring's own serial queue. See `CapturedFrameRelay`.
    ///
    /// `nonisolated let`: it is fed from `videoOutputQueue`, and it guards its own state with
    /// an `NSLock` rather than borrowing this type's actor.
    nonisolated let swingFrameBuffer = SwingFrameBuffer()

    // MARK: - Collaborators

    private let permissionManager = CameraPermissionManager()
    private let configurator = CaptureSessionConfigurator()
    private let recordingCoordinator = RecordingCoordinator()
    private let notificationHandler = CameraNotificationHandler()

    // MARK: - Internal State

    // sessionQueue-owned plumbing. @ObservationIgnored throughout: these are written on
    // sessionQueue, and the @Observable macro would otherwise drive ObservationRegistrar
    // bookkeeping from that queue — the same off-main-registrar hazard the hot callbacks
    // had. Nothing in SwiftUI observes them.
    @ObservationIgnored private var movieFileOutput: AVCaptureMovieFileOutput?
    @ObservationIgnored private var videoDataOutput: AVCaptureVideoDataOutput?
    /// Written on `sessionQueue`, read from the main thread by
    /// `makePreviewRotationSubject`. Guarded by its own lock rather than by
    /// `sessionQueue.sync` so a main-thread reader never waits behind a full
    /// `configureSession` (stopRunning + add inputs/outputs + AVAudioSession.setActive),
    /// which blocked the UI for hundreds of milliseconds on every camera entry/switch.
    /// @ObservationIgnored for the same reason as the callbacks: without it the `@Observable`
    /// macro tracks this stored property, so ObservationRegistrar bookkeeping would run on
    /// sessionQueue while `videoDeviceLock` is held. Nothing observes the capture device.
    @ObservationIgnored private let videoDeviceLock = NSLock()
    @ObservationIgnored private var _currentVideoDevice: AVCaptureDevice?
    private var currentVideoDevice: AVCaptureDevice? {
        get { videoDeviceLock.withLock { _currentVideoDevice } }
        set { videoDeviceLock.withLock { _currentVideoDevice = newValue } }
    }
    @ObservationIgnored private var captureRotationSubject: CaptureRotationSubject?
    @ObservationIgnored private var isAudioSessionConfigured = false
    @ObservationIgnored private var isSessionConfigured = false
    /// sessionQueue-only — not @Published, no main-thread requirement
    @ObservationIgnored private var isConfiguring = false
    @ObservationIgnored private var targetFrameRate: Double = 60
    /// sessionQueue-only twin of `currentCameraPosition` (which is the main-written
    /// @Observable mirror for UI). The idempotency check must not read a main-owned value.
    @ObservationIgnored private var configuredPosition: AVCaptureDevice.Position = .back

    /// Drops arrive in thermal-throttle bursts. Each main-thread @Observable
    /// write triggers a SwiftUI invalidation, so a burst floods the run loop.
    /// We coalesce into a single flush per `droppedFramesFlushInterval`.
    @ObservationIgnored private var pendingDroppedFrames: Int = 0
    @ObservationIgnored private var droppedFramesFlushScheduled = false
    private let droppedFramesLock = NSLock()
    private let droppedFramesFlushInterval: TimeInterval = 0.25
    // Duration is read directly from recordingCoordinator — no duplicate polling timer

    // MARK: - Queues

    /// `.userInitiated`. A cold bring-up is several seconds of serial system calls that the
    /// user is actively waiting on behind a disabled "Preparing camera…" button. Left at
    /// `.unspecified` the queue runs at whatever priority the enqueueing context happens to
    /// donate, so a bring-up kicked off from a low-priority launch hop was competing with
    /// StoreKit and CoreML compilation from the back of the line.
    private let sessionQueue = DispatchQueue(label: "com.golfsync.camera.session", qos: .userInitiated)
    private let videoOutputQueue = DispatchQueue(label: "com.golfsync.camera.videoOutput", qos: .userInteractive, autoreleaseFrequency: .workItem)

    // MARK: - Callbacks

    // The hot callbacks are lock-protected AND @ObservationIgnored.
    //
    // They are read on `videoOutputQueue` at 30–60 fps and on the movie-file
    // delegate queue, while being written from the main actor (beginRecording / stopRecording /
    // deactivate / stopSession). As plain `@Observable` stored properties that was two problems
    // at once: an unsynchronised cross-thread read/write of a closure, and ObservationRegistrar
    // access/mutation bookkeeping driven from a background thread at frame rate. Nothing in
    // SwiftUI observes plumbing closures, so tracking them bought nothing.
    //
    // The getters hand back a strong copy so callers invoke the closure OUTSIDE the lock —
    // holding it across the call would serialise the capture path against writers and invite
    // re-entrancy if a callback ever touched CameraService.

    @ObservationIgnored private let callbackLock = NSLock()
    @ObservationIgnored private var _onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)?
    @ObservationIgnored private var _onAudioCaptured: ((CMSampleBuffer) -> Void)?
    @ObservationIgnored private var _onRecordingFinished: ((URL?, Error?) -> Void)?

    var onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)? {
        get { callbackLock.withLock { _onFrameCaptured } }
        set { callbackLock.withLock { _onFrameCaptured = newValue } }
    }

    /// Vestigial. The session no longer carries an `AVCaptureAudioDataOutput` — nothing in
    /// the app ever consumed raw audio sample buffers, and the recorded movie's audio track
    /// comes from the movie file output — so this is never invoked. It survives only because
    /// `RecordingViewModel` still clears it in four places; remove both sides together.
    var onAudioCaptured: ((CMSampleBuffer) -> Void)? {
        get { callbackLock.withLock { _onAudioCaptured } }
        set { callbackLock.withLock { _onAudioCaptured = newValue } }
    }

    var onRecordingFinished: ((URL?, Error?) -> Void)? {
        get { callbackLock.withLock { _onRecordingFinished } }
        set { callbackLock.withLock { _onRecordingFinished = newValue } }
    }

    var onSessionInterrupted: ((CameraError.InterruptionReason) -> Void)?
    var onSessionResumed: (() -> Void)?
    var onError: ((CameraError) -> Void)?
    /// Fired on the main thread when a recording hits `RecordingCoordinator`'s
    /// maximum duration. Claimed by the live view model in `activate()`.
    @ObservationIgnored var onMaximumRecordingDurationReached: (() -> Void)?

    // MARK: - Init

    override init() {
        super.init()
        setupNotificationHandler()
        recordingCoordinator.onDurationTick = { [weak self] duration in
            DispatchQueue.main.async { self?.recordedDuration = duration }
        }
        // Fires on the main run loop. Forwarded so the live view model can stop through
        // its own state machine (finalize → save) — previously the 30-minute cap fired
        // into an unassigned closure and recording ran until the disk filled.
        recordingCoordinator.onMaximumDurationReached = { [weak self] in
            self?.onMaximumRecordingDurationReached?()
        }
    }

    deinit {
        notificationHandler.onInterrupted = nil
        notificationHandler.onInterruptionEnded = nil
        notificationHandler.onRuntimeError = nil
        deactivateAudioSession()
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let granted = await permissionManager.requestPermissions()
        if !granted {
            let status = permissionManager.checkPermissionState()
            DispatchQueue.main.async {
                self.currentError = status.video == .restricted ? .permissionRestricted : .permissionDenied
            }
        }
        return granted
    }

    func checkPermissionState() -> (video: AVAuthorizationStatus, audio: AVAuthorizationStatus) {
        permissionManager.checkPermissionState()
    }

    // MARK: - Session Setup

    /// Configure (if needed) and start the session, entirely on `sessionQueue`, returning
    /// once it is actually running. Nothing here touches the session from the caller's
    /// thread: `AVCaptureSession` serializes all API access on an internal lock, so a
    /// main-thread read taken during a slow bring-up parks the UI for the remainder of
    /// that bring-up — the first-cold-launch freeze. The Camera tab's in-place countdown
    /// covers the wait instead.
    func prepareAndStartSession(position: AVCaptureDevice.Position, frameRate: Double) async -> Bool {
        let permissions = checkPermissionState()
        #if DEBUG
        DeviceProbe.event("session_bring_up_requested", [
            "position": position == .front ? "front" : "back",
            "frame_rate": String(Int(frameRate)),
            "video_authorized": String(permissions.video == .authorized)
        ])
        #endif
        guard permissions.video == .authorized else {
            camperf("prepareAndStart DENIED — video not authorized")
            DispatchQueue.main.async { self.currentError = .permissionDenied }
            return false
        }
        return await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: self.bringUpSession(position: position, frameRate: frameRate))
            }
        }
    }

    /// sessionQueue only.
    private func bringUpSession(position: AVCaptureDevice.Position, frameRate: Double) -> Bool {
        configureSession(position: position, frameRate: frameRate)
        // A failed configuration leaves the session with no inputs. `startRunning()` on an
        // empty session "succeeds" with a black preview (see `resumeSession`), which would
        // report success upstream AND clobber the `.configurationFailed` error below with
        // nil. Surface the failure instead so callers show their recovery UI.
        guard isConfiguredFor(position: position, frameRate: frameRate) else {
            camperf("bringUpSession ABORTED — configuration failed")
            return false
        }
        if !captureSession.isRunning { startRunningWithAudioSession() }
        let running = captureSession.isRunning
        // The pivotal line of the whole timeline. `frames_seen` rides on it automatically, and
        // it asks for both artifacts: the UI snapshot says which screen is up (chrome only —
        // it can never show the preview), and the frame artifact either lands, proving the
        // pipeline delivers, or times out into `frame_capture_timeout`, proving it does not.
        #if DEBUG
        DeviceProbe.event("session_running", [
            "running": String(running),
            "position": position == .front ? "front" : "back",
            "inputs": String(captureSession.inputs.count),
            "outputs": String(captureSession.outputs.count),
            // Without this, `frames_seen: 0` is ambiguous. The probe counts frames from the
            // video-data output ONLY, so a session that never got one reports zero frames
            // while the preview and the movie output work perfectly. This prop is what
            // separates "the pipeline is dead" from "nothing was ever wired to count".
            "video_data_output": String(videoDataOutput != nil),
            "movie_output": String(movieFileOutput != nil)
        ], ui: true, frame: true)
        #endif
        DispatchQueue.main.async {
            self.isSessionRunning = running
            if running {
                self.currentError = nil
                self.isInterrupted = false
            }
        }
        return running
    }

    /// sessionQueue only. Makes repeated bring-ups idempotent: a full rebuild (stopRunning
    /// + remove/re-add every input/output + format negotiation) for parameters already in
    /// place would double the window in which the session lock is held.
    private func isConfiguredFor(position: AVCaptureDevice.Position, frameRate: Double) -> Bool {
        isSessionConfigured
            && configuredPosition == position
            && targetFrameRate == frameRate
            && !captureSession.inputs.isEmpty
    }

    /// sessionQueue only. **The only place that calls `captureSession.startRunning()`.**
    ///
    /// `automaticallyConfiguresApplicationAudioSession` is off (see
    /// `CaptureSessionConfigurator`), so AVCaptureSession no longer categorises or activates
    /// AVAudioSession on our behalf inside `startRunning`. An active, correctly categorised
    /// audio session is therefore a precondition of starting, not a side effect of it — and
    /// funnelling every start through here is what guarantees it. `configureAudioSession()`
    /// is idempotent, so paths that already configured pay nothing.
    ///
    /// Callers keep their own `isRunning` guards and context logging; this only reports the
    /// cost of the start itself.
    private func startRunningWithAudioSession() {
        configureAudioSession()
        let t0 = ProcessInfo.processInfo.systemUptime
        captureSession.startRunning()
        let startMs = elapsedMilliseconds(since: t0)
        camperf("startRunning \(startMs) running=\(captureSession.isRunning)")
        #if DEBUG
        DeviceProbe.event("configure_phase", ["phase": "start_running", "ms": startMs, "running": String(captureSession.isRunning)])
        #endif
    }

    private func configureSession(position: AVCaptureDevice.Position, frameRate: Double) {
        guard !isConfiguring else {
            camperf("configureSession SKIPPED (already configuring)")
            return
        }
        guard !isConfiguredFor(position: position, frameRate: frameRate) else {
            camperf("configureSession SKIPPED (already configured for these params)")
            return
        }
        isConfiguring = true
        defer { isConfiguring = false }

        // Phase timings. Camera start-up is several serial system calls and it is impossible to
        // tell which one is slow without measuring on a real device.
        let t0 = ProcessInfo.processInfo.systemUptime

        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        let tStop = ProcessInfo.processInfo.systemUptime
        // Bound to a local so the log line and the timeline prop are the SAME measurement,
        // not two readings of the clock a few microseconds apart.
        let stopMs = elapsedMilliseconds(since: t0)
        camperf("stopRunning \(stopMs)")
        #if DEBUG
        DeviceProbe.event("configure_phase", ["phase": "stop_running", "ms": stopMs])
        #endif

        // Ahead of the configurator, which adds the microphone input: with
        // `automaticallyConfiguresApplicationAudioSession` off the app is the only thing that
        // ever establishes the category. Do not move this below the configure call.
        configureAudioSession()
        let tAudio = ProcessInfo.processInfo.systemUptime
        let audioMs = elapsedMilliseconds(since: tStop)
        camperf("audioSession \(audioMs)")
        #if DEBUG
        DeviceProbe.event("configure_phase", ["phase": "audio_session", "ms": audioMs])
        #endif
        defer {
            let totalMs = elapsedMilliseconds(since: t0)
            camperf("configureSession TOTAL \(totalMs)")
            #if DEBUG
            DeviceProbe.event("configure_phase", ["phase": "total", "ms": totalMs])
            #endif
        }

        let (outputs, error) = configurator.configure(
            session: captureSession,
            config: .init(position: position, frameRate: frameRate),
            videoDelegate: self,
            videoQueue: videoOutputQueue,
            // `camperf` is nonisolated, so this reads as a plain (String) -> Void with no
            // actor to hop to — the probe must stay callable inline on sessionQueue.
            probe: self.camperf
        )

        if let error {
            // The configurator already emptied the session, so the previous configuration's
            // plumbing is stale: a leftover `movieFileOutput` would let `startRecording()`
            // target a detached output. The session was stopped above and is never
            // restarted on this path, so the running mirror must read false too.
            isSessionConfigured = false
            movieFileOutput = nil
            videoDataOutput = nil
            currentVideoDevice = nil
            rebuildCaptureRotation()
            DispatchQueue.main.async {
                self.isSessionRunning = false
                self.currentError = error
                self.onError?(error)
                // The user sees an alert and cannot record at all. Previously invisible in
                // production: nothing distinguished "never opened the camera" from
                // "opened it and the session refused to configure".
                Analytics.shared.track(.cameraConfigFailed(reason: String(describing: error)))
            }
            return
        }

        let configureMs = elapsedMilliseconds(since: tAudio)
        camperf("configurator.configure \(configureMs)")
        #if DEBUG
        DeviceProbe.event("configure_phase", ["phase": "configurator", "ms": configureMs])
        #endif

        movieFileOutput = outputs.movieFileOutput
        videoDataOutput = outputs.videoDataOutput
        currentVideoDevice = outputs.videoDeviceInput?.device
        configuredPosition = position
        targetFrameRate = frameRate
        isSessionConfigured = true

        rebuildCaptureRotation()

        DispatchQueue.main.async {
            self.currentCameraPosition = position
            self.sessionConfigurationId += 1
            self.currentError = nil
        }
    }

    // MARK: - Rotation

    /// Builds a `CaptureRotationSubject` that drives the device-correct rotation
    /// angle for a single preview layer. A subject is bound to one layer, since
    /// AVCaptureSession creates a distinct connection per preview layer; the
    /// Camera tab mounts exactly one `CameraPreviewView`, so exactly one subject
    /// is live at a time. Returns nil if the device isn't configured
    /// yet — the caller should ask again once the session is up.
    ///
    /// Reads `currentVideoDevice` through its own lock — never `sessionQueue.sync`, which
    /// would block the calling (main) thread for the whole of an in-flight
    /// `configureSession`. When configuration has not produced a device yet this returns
    /// nil; `RecordingView` re-asks because its preview is keyed on
    /// `sessionConfigurationId`, which `configureSession` bumps on completion.
    /// Camera start-up timing. Goes to os_log AND (Debug only) to stdout, because os_log cannot
    /// be read off a device without root — `log collect --device-udid` refuses otherwise — while
    /// stdout is captured by `devicectl device process launch --console`.
    /// `nonisolated`: every caller is already on `sessionQueue` or a capture callback queue,
    /// and it touches nothing but `AppLogger` (itself nonisolated) and `print`.
    private nonisolated func camperf(_ message: String) {
        AppLogger.camera.info("CAMPERF \(message)")
        #if DEBUG
        print("CAMPERF \(message)")
        // Every CAMPERF line reaches the timeline for free, caller strings and all. The
        // named events elsewhere are the ones a host script filters on; this is the
        // catch-all that keeps the narrative complete between them.
        DeviceProbe.event("camperf", ["msg": message])
        #endif
    }

    private nonisolated func elapsedMilliseconds(since start: Double) -> String {
        String(format: "%.0fms", (ProcessInfo.processInfo.systemUptime - start) * 1000)
    }

    func makePreviewRotationSubject(for layer: AVCaptureVideoPreviewLayer) -> CaptureRotationSubject? {
        guard let device = currentVideoDevice else { return nil }
        return CaptureRotationSubject(device: device, previewLayer: layer)
    }

    /// Detaches a preview layer's session on the main thread, but only after any in-flight
    /// `sessionQueue` work has drained. `previewLayer.session = nil` takes the session's
    /// internal lock — the one `startRunning`/`stopRunning` hold for their full duration —
    /// so detaching inline at view dismantle froze dismissal against a cold-start bring-up.
    /// Bouncing through `sessionQueue` sequences the detach behind that work; by the time
    /// the main-thread hop runs the lock is uncontended and the assignment is effectively
    /// instant, while CALayer's main-thread contract is preserved. The closure retains the
    /// layer until the deferred detach has run.
    func detachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        #if DEBUG
        DeviceProbe.event("preview_detach_requested", ["layer": DeviceProbe.identity(layer)])
        #endif
        sessionQueue.async {
            DispatchQueue.main.async {
                layer.session = nil
                #if DEBUG
                DeviceProbe.event("preview_detach_landed", ["layer": DeviceProbe.identity(layer)])
                #endif
            }
        }
    }

    /// Attach counterpart of `detachPreviewLayer`, and for the same reason. Attaching a
    /// layer to a RUNNING session adds a connection — a live graph mutation. The preview
    /// remounts on every `sessionConfigurationId` bump (camera flip, reconfigure) and on
    /// every return to the Camera tab or to the foreground, any of which can land while
    /// `sessionQueue` is mid-configure or mid-start. An inline attach on the main thread
    /// would then be a second concurrent graph mutation on a running session — observed on
    /// device as the whole preview going black. Bouncing through `sessionQueue` orders the
    /// attach after that work.
    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer, session: AVCaptureSession) {
        // The attach is deferred through two queue hops, so "requested" and "landed" can be
        // seconds apart — or the landing can never happen at all if sessionQueue is wedged
        // mid-bring-up. A request with no landing is the "preview layer was never attached"
        // half of the black-screen ambiguity, stated outright.
        #if DEBUG
        DeviceProbe.event("preview_attach_requested", ["layer": DeviceProbe.identity(layer)])
        #endif
        sessionQueue.async {
            DispatchQueue.main.async {
                layer.session = session
                // `bounds` goes along because a correctly attached layer with a zero frame is
                // a third, independent way to get a black screen — and it looks identical.
                #if DEBUG
                DeviceProbe.event("preview_attach_landed", [
                    "layer": DeviceProbe.identity(layer),
                    "session_attached": String(layer.session != nil),
                    "bounds": "\(Int(layer.bounds.width))x\(Int(layer.bounds.height))",
                    "connection": String(layer.connection != nil)
                ], ui: true, frame: true)
                #endif
            }
        }
    }

    /// Geometry needed to draw Vision pose points over the `.resizeAspectFill` preview.
    ///
    /// **Computed on sessionQueue at configure time, never on read.** `videoDataOutput` and its
    /// connection are owned by sessionQueue; deriving this in a getter meant the SwiftUI main
    /// thread touched that queue's state on every `body` evaluation — a data race, and wasted
    /// work besides. Now it is snapshotted once per configuration and handed out under a lock.
    @ObservationIgnored private let poseGeometryLock = NSLock()
    @ObservationIgnored private var _poseOverlayGeometry: PoseOverlayGeometry?

    var poseOverlayGeometry: PoseOverlayGeometry? {
        poseGeometryLock.withLock { _poseOverlayGeometry }
    }

    /// sessionQueue only. The aspect ratio is the **post-rotation** buffer ratio: the video-data
    /// connection carries a `videoRotationAngle`, so a landscape sensor arrives upright and the
    /// sensor's own ratio must be inverted for quarter turns. Mirroring is the PARITY of the two
    /// surfaces the overlay bridges: Vision analyzes the video-data buffer (forced unmirrored by
    /// the configurator), while the preview layer auto-mirrors exactly when the input is the
    /// front camera (`automaticallyAdjustsVideoMirroring` in `CameraPreviewView`). The overlay
    /// must flip whenever preview and buffer disagree — previewMirrored XOR bufferMirrored —
    /// so neither flag alone is authoritative.
    private func rebuildPoseOverlayGeometry() {
        var geometry: PoseOverlayGeometry?

        if let device = currentVideoDevice,
           let connection = videoDataOutput?.connection(with: .video) {
            let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let isQuarterTurned = connection.videoRotationAngle == 90 || connection.videoRotationAngle == 270
            let width = CGFloat(isQuarterTurned ? dimensions.height : dimensions.width)
            let height = CGFloat(isQuarterTurned ? dimensions.width : dimensions.height)
            let previewMirrored = device.position == .front
            if height > 0 {
                geometry = PoseOverlayGeometry(
                    sourceAspectRatio: width / height,
                    isMirrored: previewMirrored != connection.isVideoMirrored
                )
            }
        }

        poseGeometryLock.withLock { _poseOverlayGeometry = geometry }
    }

    private func rebuildCaptureRotation() {
        guard let device = currentVideoDevice else {
            captureRotationSubject = nil
            rebuildPoseOverlayGeometry()
            return
        }
        let subject = CaptureRotationSubject(device: device, previewLayer: nil)
        subject.register(captureConnection: videoDataOutput?.connection(with: .video))
        subject.register(captureConnection: movieFileOutput?.connection(with: .video))
        captureRotationSubject = subject
        // After registering, so the connection's videoRotationAngle is final.
        rebuildPoseOverlayGeometry()
    }

    // MARK: - Session Control

    /// Full teardown: releases the capture callbacks AND the audio session.
    ///
    /// Refuses to run while a recording is live. The callbacks are nilled synchronously here
    /// but `isSessionRunning` is only cleared asynchronously, so a spurious late call — a view
    /// teardown racing a presentation, say — used to disarm detection mid-swing with no trace
    /// beyond "no swings detected, discarding recording". `stopRecording()` clears
    /// `isRecording` synchronously, so a deliberate stop→teardown sequence still passes.
    func stopSession(caller: String = #function) {
        guard !isRecording else {
            camperf("stopSession REFUSED — recording in progress (caller=\(caller))")
            #if DEBUG
            DeviceProbe.event("session_stop_refused", ["caller": caller, "reason": "recording_in_progress"])
            #endif
            return
        }
        camperf("stopSession requested by \(caller)")
        // `caller` as a prop rather than buried in a message: a stopped session renders every
        // attached preview black, so "who stopped it" is the first question on any
        // black-screen report and the host must be able to filter on it, not regex for it.
        #if DEBUG
        DeviceProbe.event("session_stop_requested", ["caller": caller])
        #endif
        onFrameCaptured = nil
        onAudioCaptured = nil
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning { self.captureSession.stopRunning() }
            self.deactivateAudioSession()
            self.camperf("stopSession: stopped (caller=\(caller))")
            #if DEBUG
            DeviceProbe.event("session_stopped", ["caller": caller])
            #endif
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    /// The `captureSession.isRunning` early-exit deliberately lives INSIDE the queue block:
    /// reading it on the calling (main) thread serializes against any in-flight
    /// configuration and can park the UI (the first-cold-launch freeze).
    /// `caller` is captured at the call site (Swift evaluates default arguments there) —
    /// a stopped session renders every attached preview black, so knowing WHO stopped it
    /// is the first question on any black-screen report.
    func pauseSession(caller: String = #function) {
        camperf("pauseSession requested by \(caller)")
        #if DEBUG
        DeviceProbe.event("session_pause_requested", ["caller": caller])
        #endif
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            // The app's AVAudioSession is left ACTIVE (deactivating it here would fight the
            // recording coordinator's background task), but iOS routinely deactivates it for
            // us while backgrounded — and with
            // `automaticallyConfiguresApplicationAudioSession` off nothing would notice.
            // Dropping the flag forces the next start to re-establish category and activation.
            self.isAudioSessionConfigured = false
            self.camperf("pauseSession: stopped (caller=\(caller))")
            #if DEBUG
            DeviceProbe.event("session_paused", ["caller": caller])
            #endif
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    func resumeSession() {
        let permissions = checkPermissionState()
        guard permissions.video == .authorized else {
            camperf("resumeSession DENIED — video not authorized")
            DispatchQueue.main.async { self.currentError = .permissionDenied }
            return
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.captureSession.isRunning else {
                self.camperf("resumeSession no-op — already running")
                // Re-sync the mirror rather than just returning. It is the ONLY thing the UI
                // consults to enable the Start Recording button; if it ever went false while
                // the session kept running (a stop that lost its race with a start), this
                // early exit was the one path that could have corrected it and did not,
                // leaving the button disabled on "Preparing camera…" forever.
                DispatchQueue.main.async { self.isSessionRunning = true }
                return
            }
            // Configured yet? If the session has no inputs/outputs, startRunning() succeeds
            // but the preview stays BLACK — the exact symptom to distinguish from "slow to
            // start". Read here on sessionQueue: taking these reads on the main thread
            // blocked the UI for the remainder of an in-flight configureSession.
            self.camperf("resumeSession begin (configured=\(self.isSessionConfigured) inputs=\(self.captureSession.inputs.count) outputs=\(self.captureSession.outputs.count))")
            self.startRunningWithAudioSession()
            DispatchQueue.main.async {
                self.isSessionRunning = self.captureSession.isRunning
                self.currentError = nil
                self.isInterrupted = false
            }
        }
    }

    // MARK: - Camera Switching

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let newPosition: AVCaptureDevice.Position = self.configuredPosition == .back ? .front : .back
            self.reconfigure(position: newPosition)
        }
    }

    func setCamera(position: AVCaptureDevice.Position) {
        sessionQueue.async { [weak self] in
            guard let self, position != self.configuredPosition else { return }
            self.reconfigure(position: position)
        }
    }

    /// sessionQueue only. `configureSession` stops a running session and does not restart
    /// it; restore the previous running state so a camera switch doesn't leave the preview
    /// dark.
    private func reconfigure(position: AVCaptureDevice.Position) {
        let wasRunning = captureSession.isRunning
        configureSession(position: position, frameRate: targetFrameRate)
        // Same rule as `bringUpSession`: never start an empty session — a failed switch
        // must surface `configureSession`'s error, not a black preview reported as running.
        guard isConfiguredFor(position: position, frameRate: targetFrameRate) else { return }
        guard wasRunning, !captureSession.isRunning else { return }
        startRunningWithAudioSession()
        DispatchQueue.main.async { self.isSessionRunning = self.captureSession.isRunning }
    }

    // MARK: - Recording

    func startRecording() -> URL? {
        camperf("startRecording requested (session running=\(isSessionRunning), interrupted=\(isInterrupted))")
        guard let movieOutput = movieFileOutput else {
            camperf("startRecording ABORTED — no movieFileOutput")
            return nil
        }

        // Coordinator validates preconditions and returns a URL synchronously,
        // then dispatches the AVFoundation bootstrap onto `sessionQueue` so the
        // main thread is never blocked by `movieOutput.startRecording(to:)`.
        let url = recordingCoordinator.startRecording(
            movieOutput: movieOutput,
            delegate: self,
            sessionQueue: sessionQueue
        )

        if url == nil {
            DispatchQueue.main.async {
                self.currentError = .insufficientStorage
                self.onError?(.insufficientStorage)
            }
        } else {
            // Synchronous, and symmetric with `stopRecording()`: `isRecording` is the flag
            // `stopSession()` refuses on. Set asynchronously it stayed false for the rest of
            // this main-thread turn, so a teardown already sitting in the main queue would
            // pass that guard and disarm the recording we just started.
            isRecording = true
            // Armed here rather than by the view model, so the replay ring is bound to the
            // movie output's own lifetime: every route that ends a recording passes through
            // `stopRecording()` or `didFinishRecordingTo`, and both stop it.
            swingFrameBuffer.start()
            DispatchQueue.main.async {
                self.droppedFrameCount = 0
                // Zeroed here as well as in the coordinator: this is the value the REC timer
                // renders, and the coordinator's first tick is 100 ms away, so without it the
                // timer opens on the previous take's duration.
                self.recordedDuration = 0
            }
        }

        return url
    }

    /// `isRecording` drops synchronously, before the queue hop. It is what `stopSession()`
    /// guards on, and callers that stop and then tear down (RecordingViewModel.cancel) do both
    /// in one main-thread turn — an asynchronous clear would still read true at the guard and
    /// leave the session running.
    func stopRecording() {
        isRecording = false
        // Synchronously, alongside the flag: the replay tile is gone the instant the take is,
        // and the ring's couple of megabytes go with it.
        swingFrameBuffer.stop()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.recordingCoordinator.stopRecording(movieOutput: self.movieFileOutput)
        }
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        guard !isAudioSessionConfigured else { return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
            try audioSession.setActive(true)
            isAudioSessionConfigured = true
        } catch {
            AppLogger.camera.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isAudioSessionConfigured = false
    }

    // MARK: - Notifications

    private func setupNotificationHandler() {
        notificationHandler.register(for: captureSession)

        notificationHandler.onInterrupted = { [weak self] reason in
            self?.camperf("session INTERRUPTED reason=\(String(describing: reason))")
            #if DEBUG
            DeviceProbe.event("session_interrupted", ["reason": String(describing: reason)], ui: true)
            #endif
            DispatchQueue.main.async {
                self?.isInterrupted = true
                self?.currentError = .sessionInterrupted(reason)
                self?.onSessionInterrupted?(reason)
            }
        }

        notificationHandler.onInterruptionEnded = { [weak self] in
            #if DEBUG
            DeviceProbe.event("session_interruption_ended")
            #endif
            DispatchQueue.main.async {
                self?.isInterrupted = false
                self?.currentError = nil
                self?.onSessionResumed?()
            }
            self?.sessionQueue.async { [weak self] in
                guard let self, !self.captureSession.isRunning else { return }
                // An `.audioInUse` interruption is another client taking the audio route, which
                // deactivates OUR audio session. Nothing re-establishes it now that
                // AVCaptureSession no longer does, so force a full reconfigure on the way back.
                self.isAudioSessionConfigured = false
                self.camperf("interruptionEnded — restarting")
                self.startRunningWithAudioSession()
                DispatchQueue.main.async { self.isSessionRunning = self.captureSession.isRunning }
            }
        }

        notificationHandler.onRuntimeError = { [weak self] error in
            if error.code == .mediaServicesWereReset {
                // `isSessionRunning` is the right question here — "were we MEANT to be running
                // before the reset?" — but it is an @Observable property, so read it on the main
                // actor and only then hop to sessionQueue. Reading it directly on sessionQueue
                // was both an off-main @Observable access and liable to see a stale value, which
                // could silently drop the recovery and leave the camera dead after a reset.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isSessionRunning else { return }
                    self.sessionQueue.async { [weak self] in
                        guard let self, !self.captureSession.isRunning else { return }
                        // mediaservicesd restarted: every AVAudioSession the process held is
                        // invalid, whatever it reports. The flag has to be dropped or the
                        // idempotent `configureAudioSession()` would skip re-establishing it.
                        self.isAudioSessionConfigured = false
                        self.camperf("mediaServicesWereReset — restarting")
                        self.startRunningWithAudioSession()
                        DispatchQueue.main.async { self.isSessionRunning = self.captureSession.isRunning }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self?.currentError = .configurationFailed(error.localizedDescription)
                    self?.onError?(.configurationFailed(error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Copy the closure out under the lock (via the accessor), then call it with the lock
        // released. Written explicitly rather than relying on `onFrameCaptured?(...)` so the
        // copy-then-call ordering is obvious to the next reader.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // First thing done with the buffer, and the whole point of the probe: it counts every
        // frame and — only when one has been latched — encodes THIS buffer inline, so the
        // timeline can prove the pipeline is delivering. Disabled, it is one static bool read.
        #if DEBUG
        DeviceProbe.noteFrame(pixelBuffer)
        #endif
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let handler = onFrameCaptured
        handler?(pixelBuffer, timestamp)
        // After the detector, and it COPIES rather than retains. The pixel buffer belongs to the
        // capture pool and must be released with this callback — holding one starves that pool
        // and collapses the pipeline — so the ring memcpys the frame's bytes into a buffer of its
        // own and scales and encodes it on its own queue. Nothing derived from this buffer
        // outlives the callback, and the encode no longer competes with the detector for the
        // frame period. Inert unless a recording armed it. See `CapturedFrameRelay`.
        swingFrameBuffer.ingest(pixelBuffer, at: CMTimeGetSeconds(timestamp))
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        droppedFramesLock.lock()
        pendingDroppedFrames += 1
        let shouldSchedule = !droppedFramesFlushScheduled
        if shouldSchedule { droppedFramesFlushScheduled = true }
        droppedFramesLock.unlock()

        guard shouldSchedule else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + droppedFramesFlushInterval) { [weak self] in
            guard let self else { return }
            self.droppedFramesLock.lock()
            let count = self.pendingDroppedFrames
            self.pendingDroppedFrames = 0
            self.droppedFramesFlushScheduled = false
            self.droppedFramesLock.unlock()
            guard count > 0 else { return }
            self.droppedFrameCount += count
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        camperf("didFinishRecording file=\(outputFileURL.lastPathComponent) error=\(error.map { String(describing: $0) } ?? "nil")")
        #if DEBUG
        DeviceProbe.event("recording_file_finished", [
            "file": outputFileURL.lastPathComponent,
            "error": error.map { $0.localizedDescription } ?? "none",
            "has_delegate": String(onRecordingFinished != nil)
        ])
        #endif
        recordingCoordinator.markRecordingFinished()
        // The backstop for `stopRecording()`. A spontaneous stop — interruption, disk full,
        // the duration cap — lands here without anyone having asked for it, and this is the
        // one funnel every started recording passes through. Both calls are idempotent, so a
        // deliberate stop simply arrives here having already stopped.
        swingFrameBuffer.stop()
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            self?.onRecordingFinished?(outputFileURL, error)
        }
    }
}
