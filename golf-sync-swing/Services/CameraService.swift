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
    /// Holds every main-thread touch of the capture graph until the session queue is idle.
    /// Fed by `enqueueSessionWork`, which is the only way work reaches `sessionQueue`.
    private let graphGate = CaptureGraphGate()

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
    /// Preview-side twin of `captureRotationSubject`, but main-owned: built and applied from
    /// `configurePreviewConnection`.
    ///
    /// Two things make it stale, and it is worth naming both because each has its own guard. The
    /// DEVICE changes on a reconfigure — dropped on the main hop that publishes a new
    /// `sessionConfigurationId`. The LAYER changes when the Camera tab is left and re-entered,
    /// since a fresh `PreviewView` brings a fresh layer; the subject holds its layer weakly, so a
    /// stale one goes quietly nil and simply stops applying any angle. Hence the identity check
    /// below rather than a nil check alone.
    @ObservationIgnored private var previewRotationSubject: CaptureRotationSubject?
    @ObservationIgnored private weak var rotationSubjectLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var isAudioSessionConfigured = false
    @ObservationIgnored private var isSessionConfigured = false
    /// sessionQueue-only. True once `armRecordingPipeline` has installed the recording half
    /// of the graph (audio session, microphone, movie output) on top of the preview half.
    /// Dropped by `configureSession` (which empties the session) and by
    /// `disarmRecordingPipeline` (which strips the half so a preview start stays minimal).
    @ObservationIgnored private var isRecordingPipelineArmed = false
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

    /// **The only way work may reach `sessionQueue`.** Brackets the block with the graph gate,
    /// so a main-thread mutation offered while it is in flight waits instead of taking the
    /// capture session's lock behind it.
    ///
    /// A path that dispatches directly does not merely skip bookkeeping — it tells the gate the
    /// coast is clear while its own `startRunning()` holds the lock for seconds, which is the
    /// exact freeze this pair exists to prevent. `RecordingCoordinator.startRecording` is the one
    /// place that receives the queue itself; `startRecording()` brackets it with a barrier.
    ///
    /// Main-actor: `graphGate` is untouched by any other thread, and every caller is already here.
    ///
    /// Captures `self` strongly, unlike the `[weak self]` blocks it replaces. A block that must
    /// balance `workBegan()` has to run — dropped, it strands the gate above zero and every later
    /// mutation waits for a release that is never coming, which is a preview that never attaches.
    /// The block is short and already enqueued, so the strong reference outlives nothing.
    private func enqueueSessionWork(_ work: @escaping (CameraService) -> Void) {
        graphGate.workBegan()
        sessionQueue.async {
            work(self)
            DispatchQueue.main.async { self.graphGate.workEnded() }
        }
    }

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
    ///
    /// `readiness` is the phased bring-up: `.preview` starts the minimal graph (fast first
    /// frame), `.recording` additionally arms the recording half once running. See
    /// `CaptureReadiness`.
    func prepareAndStartSession(
        position: AVCaptureDevice.Position,
        frameRate: Double,
        readiness: CaptureReadiness
    ) async -> Bool {
        let permissions = checkPermissionState()
        #if DEBUG
        DeviceProbe.event("session_bring_up_requested", [
            "position": position == .front ? "front" : "back",
            "frame_rate": String(Int(frameRate)),
            "readiness": readiness.probeLabel,
            "video_authorized": String(permissions.video == .authorized)
        ])
        #endif
        guard permissions.video == .authorized else {
            camperf("prepareAndStart DENIED — video not authorized")
            DispatchQueue.main.async { self.currentError = .permissionDenied }
            return false
        }
        return await withCheckedContinuation { continuation in
            enqueueSessionWork { service in
                continuation.resume(
                    returning: service.bringUpSession(position: position, frameRate: frameRate, readiness: readiness)
                )
            }
        }
    }

    /// sessionQueue only.
    private func bringUpSession(
        position: AVCaptureDevice.Position,
        frameRate: Double,
        readiness: CaptureReadiness
    ) -> Bool {
        configureSession(position: position, frameRate: frameRate)
        // A failed configuration leaves the session with no inputs. `startRunning()` on an
        // empty session "succeeds" with a black preview (see `resumeSession`), which would
        // report success upstream AND clobber the `.configurationFailed` error below with
        // nil. Surface the failure instead so callers show their recovery UI.
        guard isConfiguredFor(position: position, frameRate: frameRate) else {
            camperf("bringUpSession ABORTED — configuration failed")
            return false
        }
        if !captureSession.isRunning {
            // A recording half left armed by an earlier take would make this start pay the
            // full-graph price the phased bring-up exists to avoid; preview starts strip it.
            if readiness == .preview { disarmRecordingPipeline() }
            startRunningForCurrentGraph()
        }
        let running = captureSession.isRunning
        if !running { reportStartFailure() }
        probeSessionRunning(running, position: position)
        publishBringUpResult(running)
        guard running, readiness == .recording else { return running }
        // Armed AFTER the start and AFTER publishing `isSessionRunning`: the preview frame
        // is already on screen while the audio route negotiates and the movie output's
        // pipeline rebuilds — the countdown's five seconds absorb both.
        return armRecordingPipeline()
    }

    /// sessionQueue only. Configuration succeeded but the start did not take (audio-route
    /// contention, mediaserverd pressure). Silent in production until now: the view retries
    /// and alerts, and the funnel finally gets the count.
    private func reportStartFailure() {
        camperf("bringUpSession start FAILED — configured but not running")
        DispatchQueue.main.async {
            Analytics.shared.track(.cameraConfigFailed(reason: "start_running"))
        }
    }

    /// The pivotal line of the whole timeline. `frames_seen` rides on it automatically, and
    /// it asks for both artifacts: the UI snapshot says which screen is up (chrome only —
    /// it can never show the preview), and the frame artifact either lands, proving the
    /// pipeline delivers, or times out into `frame_capture_timeout`, proving it does not.
    private func probeSessionRunning(_ running: Bool, position: AVCaptureDevice.Position) {
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
    }

    private func publishBringUpResult(_ running: Bool) {
        DispatchQueue.main.async {
            self.isSessionRunning = running
            if running {
                self.currentError = nil
                self.isInterrupted = false
            }
        }
    }

    /// sessionQueue only. The second configuration pass: everything a RECORDING needs that a
    /// live preview does not — the activated `.playAndRecord` audio session, the microphone
    /// input, and the movie file output with stabilization. Runs against the RUNNING session
    /// during the record countdown, so the audio-route negotiation that used to gate the
    /// first preview frame (measured 15.5–21.5 s cold, bracketing FigAudioSession err=-19224)
    /// now hides behind time the take already spends.
    ///
    /// Audio session FIRST: with `automaticallyConfiguresApplicationAudioSession` off, the
    /// category must exist before a microphone input joins the graph — the same load-bearing
    /// ordering the single-pass configure carried. Idempotent via `isRecordingPipelineArmed`.
    private func armRecordingPipeline() -> Bool {
        // Also what makes a re-tap after an abandoned countdown legal in either
        // interleaving: disarm-then-arm rebuilds the half cleanly, arm-first reuses the
        // still-attached output — both converge on a working recording.
        guard !isRecordingPipelineArmed else { return true }
        let t0 = ProcessInfo.processInfo.systemUptime
        configureAudioSession()
        let (outputs, error) = configurator.installRecordingPipeline(
            session: captureSession,
            position: configuredPosition,
            probe: camperf
        )
        reportArmOutcome(startedAt: t0, error: error)
        if let error {
            handleArmFailure(error)
            return false
        }
        movieFileOutput = outputs.movieFileOutput
        isRecordingPipelineArmed = true
        // The movie connection is new: it needs the device-correct rotation angle, and the
        // pose-overlay geometry re-snapshotted against the final graph.
        rebuildCaptureRotation()
        return true
    }

    private func reportArmOutcome(startedAt t0: Double, error: CameraError?) {
        let armMs = elapsedMilliseconds(since: t0)
        camperf("armRecordingPipeline \(armMs) error=\(error.map { String(describing: $0) } ?? "nil")")
        #if DEBUG
        DeviceProbe.event("configure_phase", ["phase": "arm_recording", "ms": armMs, "ok": String(error == nil)])
        #endif
    }

    /// The countdown owns the retry UX; this owns the truth: the specific error, the
    /// callback, and the analytics count — same trio as a configuration failure.
    private func handleArmFailure(_ error: CameraError) {
        DispatchQueue.main.async {
            self.currentError = error
            self.onError?(error)
            Analytics.shared.track(.cameraConfigFailed(reason: "arm: \(String(describing: error))"))
        }
    }

    /// sessionQueue only. Strips the recording half so the next start pays the minimal-graph
    /// price again. Two callers: a `.preview` bring-up on a STOPPED session (stale half from
    /// an earlier take), and `disarmAbandonedRecordingPipeline` after a cancelled countdown —
    /// the latter mutates a RUNNING graph, whose brief pipeline rebuild is acceptable on an
    /// idle preview. Never reachable mid-take: recording states hold the session for exactly
    /// as long as the movie output still owes a file.
    private func disarmRecordingPipeline() {
        guard isRecordingPipelineArmed else { return }
        configurator.removeRecordingPipeline(session: captureSession, probe: camperf)
        movieFileOutput = nil
        isRecordingPipelineArmed = false
        rebuildCaptureRotation()
    }

    /// A countdown armed (or is still arming) the recording pipeline and was then abandoned
    /// — CANCEL, an interruption, a backgrounding — so no take will consume it. FIFO on the
    /// session queue: an arm still in flight completes first, then this strips it, handing
    /// the microphone (and its privacy indicator) back the moment the take stops being one.
    ///
    /// The movie-output guard is belt and braces: every caller sits on a path where the
    /// recording never began (`isCountingDown` gates them), so the output is idle here by
    /// construction.
    func disarmAbandonedRecordingPipeline() {
        enqueueSessionWork { service in
            guard !(service.movieFileOutput?.isRecording ?? false) else { return }
            service.disarmRecordingPipeline()
        }
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
    /// audio session is therefore a precondition of starting — but only when the graph
    /// carries a microphone input, i.e. when the recording half is armed. The minimal
    /// preview graph has no audio anywhere, and skipping `setCategory`/`setActive` there is
    /// the phased bring-up's whole point: route negotiation is seconds with a Bluetooth
    /// device paired, and it used to gate the first preview frame.
    /// `configureAudioSession()` is idempotent, so armed paths that already configured pay
    /// nothing.
    ///
    /// Callers keep their own `isRunning` guards and context logging; this only reports the
    /// cost of the start itself.
    private func startRunningForCurrentGraph() {
        if isRecordingPipelineArmed { configureAudioSession() }
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

        // NO audio-session work here, deliberately. The preview graph carries no microphone,
        // so the category/activation — and the route negotiation they trigger — belong to
        // `armRecordingPipeline`, which the record countdown pays for. This is the deferral
        // the on-device numbers demanded: startRunning measured 15.5–21.5 s with the full
        // graph, ~50 ms of which was our code.
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
            isRecordingPipelineArmed = false
            movieFileOutput = nil
            videoDataOutput = nil
            currentVideoDevice = nil
            rebuildCaptureRotation()
            DispatchQueue.main.async {
                self.isSessionRunning = false
                self.previewRotationSubject = nil
                self.currentError = error
                self.onError?(error)
                // The user sees an alert and cannot record at all. Previously invisible in
                // production: nothing distinguished "never opened the camera" from
                // "opened it and the session refused to configure".
                Analytics.shared.track(.cameraConfigFailed(reason: String(describing: error)))
            }
            return
        }

        let configureMs = elapsedMilliseconds(since: tStop)
        camperf("configurator.configure \(configureMs)")
        #if DEBUG
        DeviceProbe.event("configure_phase", ["phase": "configurator", "ms": configureMs])
        #endif

        // Minimal graph: the recording half (microphone, movie output) is installed by
        // `armRecordingPipeline` when a countdown asks for it, never here.
        movieFileOutput = nil
        isRecordingPipelineArmed = false
        videoDataOutput = outputs.videoDataOutput
        currentVideoDevice = outputs.videoDeviceInput?.device
        configuredPosition = position
        targetFrameRate = frameRate
        isSessionConfigured = true

        // Stamped, because it was the blind spot: `configureSession TOTAL` came back 11.6s larger
        // than the sum of its published phases on device, and this is the only work between the
        // last of them and the total. Building an `AVCaptureDevice.RotationCoordinator` and
        // writing two connections' rotation angles is not obviously cheap, and unmeasured work
        // inside a measured total is worth exactly one more debugging round.
        let tOutputs = ProcessInfo.processInfo.systemUptime
        rebuildCaptureRotation()
        let rotationMs = elapsedMilliseconds(since: tOutputs)
        camperf("configure.rotation \(rotationMs)")
        #if DEBUG
        DeviceProbe.event("configure_phase", ["phase": "rotation", "ms": rotationMs])
        #endif

        DispatchQueue.main.async {
            self.currentCameraPosition = position
            self.sessionConfigurationId += 1
            // The device this was built against has just been replaced. Dropped here rather
            // than by the view, so no preview can go on applying a previous camera's angle.
            self.previewRotationSubject = nil
            self.currentError = nil
        }
    }

    // MARK: - Rotation

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

    /// Builds a `CaptureRotationSubject` that drives the device-correct rotation angle for a
    /// single preview layer. A subject is bound to one layer, since AVCaptureSession creates a
    /// distinct connection per preview layer; the Camera tab mounts exactly one
    /// `CameraPreviewView`, so exactly one subject is live at a time.
    ///
    /// Reads `currentVideoDevice` through its own lock — never `sessionQueue.sync`, which would
    /// block the calling (main) thread for the whole of an in-flight `configureSession`. Returns
    /// nil when configuration has not produced a device yet, and the caller asks again on the
    /// session's `isRunning` transition.
    private func makePreviewRotationSubject(for layer: AVCaptureVideoPreviewLayer) -> CaptureRotationSubject? {
        guard let device = currentVideoDevice else { return nil }
        return CaptureRotationSubject(device: device, previewLayer: layer)
    }

    /// Detaches a preview layer's session, on the main thread as CALayer requires, at a moment
    /// when `previewLayer.session = nil` cannot block on the capture session's internal lock.
    /// `CaptureGraphGate` carries why that matters and why the previous double queue hop did not
    /// achieve it. Leaving the Camera tab dismantles the preview and stops the session in the
    /// same turn, so this is a stall the user triggers by tapping a tab.
    ///
    /// The closure retains the layer until the deferred detach has run.
    func detachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        #if DEBUG
        DeviceProbe.event("preview_detach_requested", ["layer": DeviceProbe.identity(layer)])
        #endif
        graphGate.perform("preview_detach") {
            layer.session = nil
            #if DEBUG
            DeviceProbe.event("preview_detach_landed", ["layer": DeviceProbe.identity(layer)])
            #endif
        }
    }

    /// Attach counterpart of `detachPreviewLayer`, and for the same reason. Attaching a layer to a
    /// RUNNING session adds a connection — a live graph mutation, taking the same lock. The
    /// preview remounts on every `sessionConfigurationId` bump (camera flip, reconfigure) and on
    /// every return to the Camera tab or to the foreground, any of which can land while
    /// `sessionQueue` is mid-configure or mid-start.
    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer, session: AVCaptureSession) {
        // "requested" and "landed" can be seconds apart — or the landing can never happen at all
        // if the gate is never released. A request with no landing is the "preview layer was never
        // attached" half of the black-screen ambiguity, stated outright.
        #if DEBUG
        DeviceProbe.event("preview_attach_requested", ["layer": DeviceProbe.identity(layer)])
        #endif
        graphGate.perform("preview_attach") {
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

    /// Mirroring and rotation for a preview layer's connection — the third main-thread writer of
    /// capture-graph state, and the one that used to fire from `layoutSubviews` on every pass.
    /// Routed through the same gate as the attach, because these setters take the same lock.
    ///
    /// The layer's connection only exists once the session is attached AND configured, so this is
    /// a no-op until then and the caller is expected to ask again — `PreviewView` does, on the
    /// session's `isRunning` transition.
    /// The rotation subject is cached rather than rebuilt per call: constructing one spins up an
    /// `AVCaptureDevice.RotationCoordinator`, and this now runs on every `isRunning` transition.
    /// It is dropped wherever `currentVideoDevice` changes, which is the only thing that can make
    /// it stale.
    func configurePreviewConnection(_ layer: AVCaptureVideoPreviewLayer) {
        graphGate.perform("preview_connection") { [weak self] in
            guard let self, let connection = layer.connection else { return }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = true
            }
            if self.previewRotationSubject == nil || self.rotationSubjectLayer !== layer {
                self.previewRotationSubject = self.makePreviewRotationSubject(for: layer)
                self.rotationSubjectLayer = layer
            }
            self.previewRotationSubject?.applyPreviewAngle()
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
        enqueueSessionWork { service in
            if service.captureSession.isRunning { service.captureSession.stopRunning() }
            service.deactivateAudioSession()
            service.camperf("stopSession: stopped (caller=\(caller))")
            #if DEBUG
            DeviceProbe.event("session_stopped", ["caller": caller])
            #endif
            DispatchQueue.main.async { service.isSessionRunning = false }
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
        enqueueSessionWork { service in
            guard service.captureSession.isRunning else { return }
            service.captureSession.stopRunning()
            // The app's AVAudioSession is left ACTIVE (deactivating it here would fight the
            // recording coordinator's background task), but iOS routinely deactivates it for
            // us while backgrounded — and with
            // `automaticallyConfiguresApplicationAudioSession` off nothing would notice.
            // Dropping the flag forces the next start to re-establish category and activation.
            service.isAudioSessionConfigured = false
            service.camperf("pauseSession: stopped (caller=\(caller))")
            #if DEBUG
            DeviceProbe.event("session_paused", ["caller": caller])
            #endif
            DispatchQueue.main.async { service.isSessionRunning = false }
        }
    }

    func resumeSession() {
        let permissions = checkPermissionState()
        guard permissions.video == .authorized else {
            camperf("resumeSession DENIED — video not authorized")
            DispatchQueue.main.async { self.currentError = .permissionDenied }
            return
        }
        enqueueSessionWork { service in
            guard !service.captureSession.isRunning else {
                service.camperf("resumeSession no-op — already running")
                // Re-sync the mirror rather than just returning. It is the ONLY thing the UI
                // consults to enable the Start Recording button; if it ever went false while
                // the session kept running (a stop that lost its race with a start), this
                // early exit was the one path that could have corrected it and did not,
                // leaving the button disabled on "Preparing camera…" forever.
                DispatchQueue.main.async { service.isSessionRunning = true }
                return
            }
            // Configured yet? If the session has no inputs/outputs, startRunning() succeeds
            // but the preview stays BLACK — the exact symptom to distinguish from "slow to
            // start". Read here on sessionQueue: taking these reads on the main thread
            // blocked the UI for the remainder of an in-flight configureSession.
            service.camperf("resumeSession begin (configured=\(service.isSessionConfigured) inputs=\(service.captureSession.inputs.count) outputs=\(service.captureSession.outputs.count))")
            service.startRunningForCurrentGraph()
            DispatchQueue.main.async {
                service.isSessionRunning = service.captureSession.isRunning
                service.currentError = nil
                service.isInterrupted = false
            }
        }
    }

    // MARK: - Camera Switching

    func switchCamera() {
        enqueueSessionWork { service in
            let newPosition: AVCaptureDevice.Position = service.configuredPosition == .back ? .front : .back
            service.reconfigure(position: newPosition)
        }
    }

    func setCamera(position: AVCaptureDevice.Position) {
        enqueueSessionWork { service in
            guard position != service.configuredPosition else { return }
            service.reconfigure(position: position)
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
        startRunningForCurrentGraph()
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
        // The coordinator receives the queue itself and dispatches its own bootstrap onto it, so
        // it is the one path that cannot bracket the gate from the inside. An empty block behind
        // it does the job: the queue is serial, so the gate is not released until the bootstrap
        // has run, and `movieOutput.startRecording(to:)` takes the graph lock like everything
        // else here. Raising the gate only AFTER the coordinator's dispatch leaves no window —
        // this method is synchronous on the main thread, so no mutation can land between the two.
        enqueueSessionWork { _ in }

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
        enqueueSessionWork { service in
            service.recordingCoordinator.stopRecording(movieOutput: service.movieFileOutput)
        }
    }

    // MARK: - Audio Session

    /// Timed in two halves, because they fail and stall for different reasons and the sum hides
    /// which. `setCategory` negotiates the route — the expensive part when a Bluetooth device is
    /// paired, since `.allowBluetoothA2DP` makes it a candidate. `setActive(true)` is where
    /// another app holding the route, or this app not being frontmost, shows up.
    private func configureAudioSession() {
        guard !isAudioSessionConfigured else { return }
        let audioSession = AVAudioSession.sharedInstance()
        let t0 = ProcessInfo.processInfo.systemUptime
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: audioCategoryOptions())
            let categoryMilliseconds = elapsedMilliseconds(since: t0)
            let tCategory = ProcessInfo.processInfo.systemUptime
            try audioSession.setActive(true)
            camperf("audio.setCategory \(categoryMilliseconds) audio.setActive \(elapsedMilliseconds(since: tCategory))")
            isAudioSessionConfigured = true
        } catch {
            // Through `camperf` as well as the logger: this failure leaves `startRunning()`
            // reporting `running=false` and the screen stuck on "Preparing camera…", so it
            // belongs in the same stream as the timings that explain the wait.
            camperf("audio session FAILED after \(elapsedMilliseconds(since: t0)) — \(error.localizedDescription)")
            AppLogger.camera.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    /// `.defaultToSpeaker` is not negotiable — without it a `.playAndRecord` session routes
    /// playback to the earpiece, which makes every replay silent-sounding. The other two are
    /// convenience, and each is a `CaptureExperiment` knob because each is a candidate for the
    /// audio-route negotiation that `startRunning` waits on.
    private func audioCategoryOptions() -> AVAudioSession.CategoryOptions {
        let experiment = CaptureExperiment.current
        var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker]
        if experiment.includesBluetoothAudio { options.insert(.allowBluetoothA2DP) }
        if experiment.includesMixWithOthers { options.insert(.mixWithOthers) }
        return options
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
            // Both halves on the main thread. The notification arrives on an arbitrary thread,
            // and `enqueueSessionWork` touches the gate's count — main-owned, and the one thing
            // that tells a preview mutation to wait. Enqueueing from here directly would let the
            // count be raised after the restart had already begun.
            DispatchQueue.main.async {
                guard let self else { return }
                self.isInterrupted = false
                self.currentError = nil
                self.onSessionResumed?()
                self.enqueueSessionWork { service in
                    guard !service.captureSession.isRunning else { return }
                    // An `.audioInUse` interruption is another client taking the audio route,
                    // which deactivates OUR audio session. Nothing re-establishes it now that
                    // AVCaptureSession no longer does, so force a full reconfigure on the way back.
                    service.isAudioSessionConfigured = false
                    service.camperf("interruptionEnded — restarting")
                    service.startRunningForCurrentGraph()
                    DispatchQueue.main.async { service.isSessionRunning = service.captureSession.isRunning }
                }
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
                    self.enqueueSessionWork { service in
                        guard !service.captureSession.isRunning else { return }
                        // mediaservicesd restarted: every AVAudioSession the process held is
                        // invalid, whatever it reports. The flag has to be dropped or the
                        // idempotent `configureAudioSession()` would skip re-establishing it.
                        service.isAudioSessionConfigured = false
                        service.camperf("mediaServicesWereReset — restarting")
                        service.startRunningForCurrentGraph()
                        DispatchQueue.main.async { service.isSessionRunning = service.captureSession.isRunning }
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
