//
//  RecordingView.swift
//  golf-sync-swing
//
//  The Camera tab. One screen, ONE `AVCaptureVideoPreviewLayer`, chrome driven by
//  `RecordingViewModel.state`.
//
//  The session is brought up when the tab appears — entirely on the camera's session queue
//  (`prepareAndStartSession`), so mounting the tab never blocks the main thread — and stopped
//  when the user leaves it. Start Recording runs the countdown IN PLACE: there is no second
//  screen to present and no second preview layer to attach. Attaching one to an already-running
//  session is what turned the preview black — first when the capture screen was presented over
//  this one, then again when the PiP tile mounted on the first detected swing.
//
//  The consequence that shapes every handler below: a take is NOT modal. The tab bar is hidden
//  for the duration of one — see the `.toolbar` scope in `body` — but that is presentation, not
//  a lock: `.reviewing` keeps the bar on purpose so the user can go free a library slot, a tap
//  can still land while the bar animates away, and backgrounding needs no bar at all. So every
//  point of a take remains reachable from outside it.
//  `warmUpCamera` holds the one policy that follows (only the visible tab may light the camera);
//  the lifecycle handlers decide what a take left behind is owed.
//

import SwiftUI
import SwiftData
import AVFoundation

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = RecordingViewModel()
    @State private var videoAuthorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var showingError = false
    @State private var showDetectionFlash = false
    @Namespace private var silhouetteAnimation

    private var hasCameraAccess: Bool { videoAuthorization == .authorized }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if hasCameraAccess {
                captureSurface
            } else {
                CameraPermissionGate(
                    status: videoAuthorization,
                    onPrimaryAction: handlePermissionAction
                )
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: viewModel.isCountingDown)
        // THE TAKE IS THE SCREEN, tab bar included — from the moment the countdown starts until
        // the take is resolved. Every layer above already draws under the bar (they ignore the
        // safe area) but the bar is drawn OVER everything, so a strip of the app's furniture sat
        // on top of a countdown, a live recording and a full-screen swing alike and gave the
        // illusion away. Scoping this to the replay only, as it first did, hid the bar in the
        // one state nobody was complaining about.
        //
        // A ternary, deliberately, and not a pair of imperative calls: the bar's visibility is a
        // FUNCTION of `viewModel.state`, so every route out of a take puts it back without
        // anyone having to remember to — including the routes no button triggers (the movie
        // output's own delegate, the maximum-duration cap, the finalize watchdog's recovery, a
        // countdown abandoned by a backgrounding or an interruption).
        //
        // `isReplayOnMain` is no longer a term of its own, and nothing was lost by that: it is
        // `activeReplay != nil && displayMode == .swingOnMain`, `activeReplay` is nil outside
        // `.recording`, and `.recording` hides the bar unconditionally — so `.recording`
        // subsumes it. The chain is written out because a change that let a replay outlive
        // `.recording` would have to come back to this line.
        //
        // NOBODY IS TRAPPED. Each hidden state, and what leaves it:
        //  * `.countdown` — `CountdownView`'s CANCEL button, always rendered, and the top bar's
        //    xmark (`RecordingTopBar.showsCancel` covers `.countdown`). It also gives up on its
        //    own: the wait for the session is bounded by `sessionStartTimeout` (8s) and lands
        //    back in `.idle` with an error to retry from, so even a countdown that never ticks
        //    cannot hold the screen.
        //  * `.recording` — Stop, the top bar's xmark, and the 30-minute cap. The swap tile
        //    stays reachable above the replay cover, and swapping no longer changes the bar at
        //    all: both surfaces belong to the same take.
        //  * `.finalizingVideo` / `.saving` — no affordance, BY DESIGN: the overlay blocks input
        //    because a half-written file and a half-finished copy must not be interrupted. Both
        //    exit by themselves (`onRecordingFinished`, `completePersistence`), and
        //    `startFinalizeWatchdog` recovers either one into `.reviewing` after 20s — which
        //    brings the bar back for free, visibility being a function of state.
        //
        // `.reviewing` KEEPS THE BAR. A finished take waiting for Save or Delete is a state the
        // user may legitimately want to leave: the library gate's paywall tells them to go free
        // a slot in History, and hiding the bar there would strand them in front of the very
        // instruction they were just given. It costs the take nothing — `handleCameraTabLeft`
        // keeps the file and the review panel and merely hands the camera back, and `onAppear`
        // re-claims the callbacks on the way in — so the take survives the trip.
        //
        // `isCameraTabSelected` is load-bearing now rather than belt-and-braces. Under the old
        // scope a hidden bar could not outlive the tab change; under this one a take
        // deliberately does — `handleCameraTabLeft` breaks on `.countdown`, `.finalizingVideo`,
        // `.saving` and `.saved` rather than abandoning work in flight, and `.recording` leaves
        // through `stopRecording()` into a `.finalizingVideo` that can run for seconds with
        // History already on screen. This term is what keeps this screen from publishing
        // `.hidden` for furniture it is not currently showing, instead of resting on SwiftUI
        // resolving the preference from the selected tab.
        //
        // The bottom controls slide down as the safe area shrinks — the screen getting taller is
        // the point, and `RecordingControlsView` clears the bar by a fixed 100pt rather than by
        // measuring it, so nothing ends up underneath anything. Stop now sits at the same height
        // for every recording instead of moving when a replay took the main surface.
        //
        // Not `.id(...)`, not a `fullScreenCover`, and nothing at all added to `cameraPreview`:
        // the one preview layer stays mounted and full-screen through the whole take (it ignores
        // the safe area, so even its bounds do not change), which is the rule this file exists
        // to keep.
        .toolbar(isTakeInProgress && isCameraTabSelected ? .hidden : .visible, for: .tabBar)
        .onAppear(perform: handleAppear)
        .onChange(of: router.selectedTab) { _, tab in handleTabChange(tab) }
        .onChange(of: scenePhase) { _, phase in handleScenePhaseChange(phase) }
        .onChange(of: viewModel.state) { previous, current in
            handleStateChange(from: previous, to: current)
        }
        .onChange(of: viewModel.swingCount) { previous, current in
            flashDetection(from: previous, to: current)
        }
        .onChange(of: viewModel.cameraService.isInterrupted) { _, interrupted in
            // Mirrors the `.background` abort: the countdown must not run to completion
            // behind the InterruptionOverlay and start recording against a session that
            // is delivering no frames.
            guard interrupted else { return }
            viewModel.abortCountdown()
        }
        .onChange(of: viewModel.cameraService.currentError) { _, error in
            presentError(if: error != nil)
        }
        .onChange(of: viewModel.errorMessage) { _, message in
            presentError(if: message != nil)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                showingError = false
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage
                 ?? viewModel.cameraService.currentError?.errorDescription
                 ?? String(localized: "An unknown error occurred", comment: "Fallback capture-error alert body when neither the ViewModel nor CameraService provided a message"))
        }
        .fullScreenCover(isPresented: Bindable(viewModel).requiresLibraryUpgrade) {
            AppPaywallView(source: .featureGate) {
                viewModel.requiresLibraryUpgrade = false
            }
        }
    }

    // MARK: - Layers

    /// The preview is mounted for the whole life of the tab and every other layer draws over
    /// it, so nothing here ever attaches a second layer to the running session.
    private var captureSurface: some View {
        ZStack {
            cameraPreview
            warmUpVeil
            replayCover
            skeletonOverlay
            positioningGuide
            countdownOverlay
            chrome
            statusOverlays
        }
    }

    /// configurationId is passed as data, NOT as `.id(...)`: identity-keying tore the
    /// preview down and re-attached `previewLayer.session` on the main thread mid
    /// bring-up, which serializes against sessionQueue (the first-launch freeze).
    private var cameraPreview: some View {
        CameraPreviewView(
            session: viewModel.cameraService.captureSession,
            configurationId: viewModel.cameraService.sessionConfigurationId,
            rotationSubjectProvider: { [weak service = viewModel.cameraService] layer in
                service?.makePreviewRotationSubject(for: layer)
            }
        )
        .ignoresSafeArea()
    }

    /// A session coming up delivers a stuttering handful of frames a second, and a preview
    /// juddering at 4fps reads as a broken camera rather than a starting one. Frosting it
    /// until `isSessionRunning` hides the frame rate without hiding that there is a camera
    /// back there, and fading the frost out lets the picture "focus in" instead of snapping.
    ///
    /// A MATERIAL, not `.blur(radius:)`: the preview is a render-server surface that SwiftUI
    /// cannot sample — the same reason snapshots of it come out black — so a blur modifier
    /// would find nothing to blur. `RecordingTopBar` already frosts this exact preview.
    ///
    /// A sibling slot in the ZStack, never a modifier on `cameraPreview`: extending that
    /// view's chain is the class of change that blacked out the screen twice. Mounted only
    /// while it is needed, so no backdrop pass survives onto the recording path — and the
    /// animation sits on this always-present container, which is what the removal transition
    /// reads its timing from.
    ///
    /// The colour scheme is pinned because the sibling tabs prefer `.light` and a light
    /// frost over a camera is a white haze; this screen is black chrome and white text.
    private var warmUpVeil: some View {
        ZStack {
            if !isCameraReady {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.45), value: isCameraReady)
    }

    /// The last detected swing, looping over the whole screen, when the user's mode puts it
    /// there. It COVERS the preview; it does not replace it. The single
    /// `AVCaptureVideoPreviewLayer` stays mounted and untouched underneath — which is why
    /// swapping back is instant, and why this cannot reproduce the black screen that
    /// attaching a second layer caused twice.
    ///
    /// A sibling slot in the ZStack, mounted and unmounted on its own, never a modifier on
    /// `cameraPreview`: extending that view's chain is the class of change that blacked out
    /// the screen. Same rule the warm-up veil follows, for the same reason. The animation
    /// sits on this always-present container, which is what the transition reads its timing
    /// from.
    ///
    /// Not hit-testable: the swap is the tile's, and a full-screen tap target over a live
    /// capture screen would swallow gestures meant for the chrome above it.
    private var replayCover: some View {
        ZStack {
            if let replay = viewModel.activeReplay, viewModel.isReplayOnMain {
                ZStack {
                    Color.black
                    SwingReplayPlayerView(replay: replay, isMirrored: isPreviewMirrored)
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isReplayOnMain)
    }

    /// Shares the preview's coordinate space. Geometry is re-read per configuration
    /// because switching camera changes both the post-rotation aspect and mirroring.
    ///
    /// Suppressed while the replay covers the screen. These joints are the pose of the frame
    /// arriving NOW; the picture underneath is a moment that already finished happening, so
    /// drawing one over the other would put the golfer's skeleton somewhere the golfer isn't.
    /// It is not moved onto the tile's live camera either — a 120×160 thumbnail is not a place
    /// anyone reads joint positions. The toggle stays where it is and takes effect the instant
    /// the surfaces swap back.
    @ViewBuilder
    private var skeletonOverlay: some View {
        // `drawsSkeleton` is the same conjunction the view model gates its pose subscription on —
        // read it rather than re-deriving it, or the overlay and the subscription can drift apart.
        if viewModel.drawsSkeleton, let geometry = viewModel.cameraService.poseOverlayGeometry {
            SkeletonOverlayView(jointMap: viewModel.latestJointMap, geometry: geometry)
                .id("capture-skeleton-\(viewModel.cameraService.sessionConfigurationId)")
                .ignoresSafeArea()
        }
    }

    /// Framing guidance, only while no take is running. It hands its silhouette to
    /// `CountdownView` through `silhouetteAnimation`, so the two must never share the screen.
    @ViewBuilder
    private var positioningGuide: some View {
        if viewModel.state == .idle {
            PositioningGuideOverlay(silhouetteNamespace: silhouetteAnimation)
        }
    }

    @ViewBuilder
    private var countdownOverlay: some View {
        if viewModel.isCountingDown {
            CountdownView(
                count: viewModel.countdownValue,
                onCancel: viewModel.discardTake,
                silhouetteNamespace: silhouetteAnimation,
                isCameraReady: isCameraReady
            )
            .transition(.opacity)
        }
    }

    private var chrome: some View {
        CaptureChromeView(viewModel: viewModel, isCameraReady: isCameraReady)
    }

    @ViewBuilder
    private var statusOverlays: some View {
        finalizingOverlay

        // `.reviewing` pauses the session by design, so this panel is what the user sees
        // instead of a black preview — and it is where "no swing detected" is finally said
        // out loud, next to the Save/Delete buttons that act on it.
        if viewModel.isReviewing {
            ReviewNoticeOverlay(notice: viewModel.currentReviewNotice)
        }

        if viewModel.cameraService.isInterrupted {
            InterruptionOverlay(
                errorDescription: viewModel.cameraService.currentError?.errorDescription,
                onResume: viewModel.cameraService.resumeSession
            )
        }

        if showDetectionFlash {
            Color.fairwayGreen.opacity(0.35)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// One overlay, two honest phases: writing the file is not saving it, and the app does
    /// not yet know which of the two the take will get.
    @ViewBuilder
    private var finalizingOverlay: some View {
        if viewModel.isSaving {
            FinalizingVideoOverlay(phase: .saving, swingCount: viewModel.swingCount)
        } else if viewModel.isFinalizingVideo {
            FinalizingVideoOverlay(phase: .finalizing, swingCount: viewModel.swingCount)
        }
    }

    // MARK: - Lifecycle

    private func handleAppear() {
        viewModel.modelContext = modelContext
        refreshVideoAuthorization()
        #if DEBUG
        DeviceProbe.event("camera_tab_appeared", [
            "has_access": String(hasCameraAccess),
            "state": viewModel.state.probeLabel,
            "session_running": String(viewModel.cameraService.isSessionRunning)
        ], ui: true)
        #endif
        // Claims the shared camera's callbacks for THIS instance. SwiftUI builds a throwaway
        // view model on every tab switch and discards all but the installed one, and only the
        // installed one ever reaches `onAppear` — which also fires on every RETURN to the
        // tab, so a take preserved in `.reviewing` gets its callbacks back right here.
        viewModel.activate()
        warmUpCamera()
    }

    /// Teardown is driven by the tab selection, NOT by `onDisappear`, which also fires when
    /// this view merely presents the library-upgrade paywall — tearing down then destroyed
    /// the recording the user was being asked to pay to keep.
    ///
    /// What leaving costs depends entirely on what the take is doing, so the view model owns
    /// that decision. Work that was still in flight when the user walked away keeps the
    /// camera until it lands; `handleStateChange` is where it is finally let go.
    private func handleTabChange(_ tab: AppRouter.Tab) {
        guard tab != .camera else { return }
        viewModel.handleCameraTabLeft()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background: handleBackground()
        case .active: handleForeground()
        default: break
        }
    }

    private func handleBackground() {
        // A countdown cannot survive backgrounding: the session is about to pause, and
        // letting the countdown finish would record against a stopped session and surface a
        // spurious "Camera session is not running." alert.
        viewModel.abortCountdown()
        // Only pause when not mid-capture; interrupting an in-flight recording would lose it.
        guard !viewModel.isRecording else { return }
        viewModel.cameraService.pauseSession()
    }

    /// `onAppear` does not fire again on foreground, so this is the only place that can
    /// notice a permission granted in Settings — without the re-read the gate stays up,
    /// still offering the "Open Settings" button the user has already obeyed, until the app
    /// is relaunched.
    private func handleForeground() {
        refreshVideoAuthorization()
        // An interruption (call banner, FaceTime PiP) leaves the session RUNNING, and a
        // bring-up would clear `isInterrupted` and dismiss an overlay that is still true.
        guard !isCameraReady else { return }
        // Mirror of the `.background` pause: nothing else relights a deliberately paused
        // session. `prepareAndStartSession` rather than `resumeSession`, because a
        // permission just granted in Settings leaves a session that was never CONFIGURED,
        // and resuming that one starts an input-less session — a black preview stuck on
        // "Preparing camera…". It clears a stuck `isInterrupted` just the same.
        warmUpCamera()
    }

    private func handleStateChange(from previous: RecordingState, to current: RecordingState) {
        switch current {
        case .saved:
            handleSaveCompleted()
        // Work that was in flight when the user left the tab has now landed. Both quiescent
        // states get the camera handed back here — `handleCameraTabLeft` deliberately left it
        // alone until the write or the copy finished. Nothing is deleted: `releaseCamera`
        // stops the session, and a take waiting in `.reviewing` keeps its file and its panel
        // for whenever the user comes back.
        case .reviewing where !isCameraTabSelected:
            viewModel.releaseCamera()
        case .idle where !isCameraTabSelected:
            viewModel.releaseCamera()
        case .idle where previous == .reviewing:
            // `.reviewing` is the one state that pauses the session, so the review panel is
            // not read over a live preview. Both exits from it — Delete and the top bar's
            // close button — owe the ready screen its preview back.
            warmUpCamera()
        default:
            break
        }
    }

    /// The surviving detection feedback, alongside the top bar's swing-count badge.
    private func flashDetection(from previous: Int, to current: Int) {
        guard current > previous, viewModel.isRecording else { return }
        withAnimation(.easeOut(duration: 0.15)) { showDetectionFlash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeIn(duration: 0.25)) { showDetectionFlash = false }
        }
    }

    /// The access check keeps a permission failure from stacking an alert on top of
    /// `CameraPermissionGate`, which is already saying the same thing with a button that fixes it.
    private func presentError(if hasError: Bool) {
        guard hasError, hasCameraAccess else { return }
        showingError = true
    }

    /// Fire-and-forget session bring-up; all real work happens on the camera's session queue.
    /// Idempotent: `configureSession` skips when already configured, `startRunning` when running.
    ///
    /// The guard is the whole "who may light the camera" policy, in one place because every
    /// caller can be reached from under another tab: a foreground, or a permission grant
    /// whose `Task` resumes after the user has moved on. Lighting the camera from a screen
    /// with no preview on it turns on the green privacy indicator and re-activates the
    /// `.playAndRecord` audio session, taking the route from whatever they were playing.
    /// `.idle` only — `.reviewing` keeps the preview dark behind the review panel, and the
    /// in-flight states already own the session.
    private func warmUpCamera() {
        // Recorded before the guard, with each of its three terms broken out: this policy is
        // the reason the camera silently stays dark, and "which term said no" is otherwise
        // invisible from outside.
        #if DEBUG
        DeviceProbe.event("warm_up_camera", [
            "has_access": String(hasCameraAccess),
            "camera_tab_selected": String(isCameraTabSelected),
            "state": viewModel.state.probeLabel,
            "accepted": String(hasCameraAccess && isCameraTabSelected && viewModel.state == .idle)
        ])
        #endif
        guard hasCameraAccess, isCameraTabSelected, viewModel.state == .idle else { return }
        Task {
            _ = await viewModel.cameraService.prepareAndStartSession(position: .front, frameRate: 30)
        }
    }

    private var isCameraReady: Bool { viewModel.cameraService.isSessionRunning }

    private var isCameraTabSelected: Bool { router.selectedTab == .camera }

    /// A take is under way, so the app's own furniture has no business on the screen. The tab
    /// bar's visibility is DERIVED from this rather than tracked; the `.toolbar` modifier in
    /// `body` carries the reasoning, including the way out of every state named here.
    ///
    /// Exhaustive over `RecordingState`, no `default`: a new state has to be classified rather
    /// than silently inheriting a visible bar — the same reason `holdsNoCameraWork` and
    /// `RecordingTopBar.showsCancel` spell theirs out.
    ///
    /// Two states are deliberately NOT a take in progress. `.reviewing` is a decision the user
    /// is allowed to walk away from, and walking away preserves the take by design. `.saved` has
    /// no control of any kind on screen — no cancel, no buttons, no overlay — and no watchdog
    /// behind it, so hiding the bar there could only ever trap someone; it also resolves inside
    /// the same main-actor turn it is entered in, because `handleSaveCompleted` calls
    /// `dismissSavedState()` ahead of every guard and branch, so the bar gets no frame to
    /// flicker in.
    private var isTakeInProgress: Bool {
        switch viewModel.state {
        case .countdown, .recording, .finalizingVideo, .saving: return true
        case .idle, .reviewing, .saved: return false
        }
    }

    /// The same parity `CaptureChromeView` flips its tile by: replay frames come from the
    /// video-data output, which the configurator forces unmirrored, while the front camera's
    /// preview auto-mirrors. Without it the full-screen replay would play the swing back the
    /// wrong way round over a preview that had it the right way round.
    private var isPreviewMirrored: Bool {
        viewModel.cameraService.poseOverlayGeometry?.isMirrored ?? false
    }

    // MARK: - Permission

    private func refreshVideoAuthorization() {
        videoAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func handlePermissionAction() {
        switch videoAuthorization {
        case .notDetermined:
            Task {
                _ = await viewModel.cameraService.requestPermissions()
                refreshVideoAuthorization()
                // Freshly granted → light up the ready screen's preview right away.
                warmUpCamera()
            }
        case .denied, .restricted:
            openSystemSettings()
        default:
            break
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Save Hand-off

    private func handleSaveCompleted() {
        let outcome = viewModel.saveOutcome
        viewModel.dismissSavedState()
        // A save can finish after the user has left — Stop, then Settings. Navigating then
        // yanks them into a History detail they never asked for, and if they are ALREADY on
        // History `selectedTab = .history` is a no-op assignment that fires no `onChange`, so
        // the teardown the tab-change handler owns would never run. Released explicitly here
        // as well as by `handleStateChange`'s `.idle` case: the camera must not depend on the
        // ordering of a re-entrant `onChange`.
        guard isCameraTabSelected else {
            viewModel.releaseCamera()
            return
        }
        // Nowhere to navigate means we are staying on this tab, and `onRecordingFinished`
        // paused the session before the save — so relight it. Deliberately handled here
        // rather than as another `→ .idle` case in `handleStateChange`: that would also fire
        // on the navigating branch, and `warmUpCamera`'s `Task` hop can land its
        // `startRunning` behind the teardown's `stopRunning`, leaving the camera lit on
        // another tab.
        guard let outcome else {
            warmUpCamera()
            return
        }
        router.openInHistory(videoID: outcome.videoID)
    }
}

#Preview {
    RecordingView()
        .environment(AppRouter())
}
