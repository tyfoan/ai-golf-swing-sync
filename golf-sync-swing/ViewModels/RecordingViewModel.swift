//
//  RecordingViewModel.swift
//  golf-sync-swing
//
//  Orchestrator for recording workflow.
//  Delegates to collaborators:
//    CameraService - Camera session management
//
//  Types: RecordingTypes.swift (RecordingState, SwingClip)
//

import SwiftUI
import SwiftData
import AVFoundation
import CoreMedia
// `ProcessInfo.systemUptime` (the settle clock) and `String(format:)`: MemberImportVisibility
// counts only direct imports, so Foundation is named here rather than leaned on through
// AVFoundation.
import Foundation
import os

@MainActor
@Observable
final class RecordingViewModel {

    // MARK: - State

    var state: RecordingState = .idle
    var detectedSwings: [SwingClip] = []
    var recordingURL: URL?

    // MARK: - UI State

    var playbackSpeed: Float = 1.0
    var errorMessage: String?
    /// Why the screen is sitting in `.reviewing`. Kept apart from `errorMessage` on
    /// purpose: RecordingView turns any non-nil `errorMessage` into an "Error" alert, and
    /// "no swing detected" is an outcome the user decides about, not a failure to dismiss.
    var reviewNotice: ReviewNotice?
    var requiresLibraryUpgrade: Bool = false
    private(set) var saveOutcome: SaveOutcome?

    /// Live skeleton overlay, as the user asked for it. What actually gets subscribed to is
    /// `drawsSkeleton` — the toggle is only half of the answer, because a replay covering the
    /// screen hides the overlay just as thoroughly as switching it off. Defaults on: it's the
    /// feature that makes the capture screen read as "analysing".
    var isSkeletonEnabled: Bool = true {
        didSet {
            guard oldValue != isSkeletonEnabled else { return }
            applySkeletonSubscription()
        }
    }

    /// Most recent skeleton, in Vision's normalized space. `PoseOverlayGeometry` maps it.
    private(set) var latestJointMap: BodyJointMap?

    /// What the picture-in-picture tile is showing: the most recently detected swing, as
    /// frames pulled from `CameraService.swingFrameBuffer`. Never the recording file (opening
    /// it mid-write makes iOS terminate the capture) and never a live camera feed (a second
    /// preview layer blacked out the main preview).
    ///
    /// Published in two steps, and the first one carries no frames at all: a swing appears here
    /// the instant it is detected, `SwingReplay.loading` set, so the surface can draw the wait
    /// for its own tail. Back to nil if that wait ends with nothing in the ring for the range —
    /// the tile is absent rather than empty, and never a bar that has nothing behind it. Back to nil
    /// too if the system's memory pressure empties the ring under it, because these frames are a
    /// retain on the ring's own bytes (`abandonReplayUnderMemoryPressure`).
    ///
    /// Whatever is HERE is what the golfer is watching, which is why the two teardown paths are
    /// conditional rather than blanket: a swing whose pull came back empty may only take down its own
    /// loading surface, never a replay that is playing.
    ///
    /// Observed, because it is half of `isReplayOnMain` and therefore half of whether a
    /// skeleton is worth computing. The first replay of a take arrives as a mode change
    /// FOLLOWED by this assignment — re-applying on the mode alone would read a still-nil
    /// replay, conclude nothing covers the screen, and subscribe to poses that never get drawn.
    private(set) var swingReplay: SwingReplay? {
        didSet { applySkeletonSubscription() }
    }

    /// Which surface the last detected swing is on — and therefore which one the live camera
    /// is on, because they are always opposite.
    ///
    /// Nothing here moves a camera preview. There is ONE `AVCaptureVideoPreviewLayer`, mounted
    /// full-screen for the life of the tab, and it stays put in both modes: `.swingOnMain`
    /// draws the replay over it and feeds the tile from the ring buffer, `.cameraOnMain` draws
    /// nothing over it and puts the replay in the tile. No layer is created, destroyed or
    /// moved, which is why the swap is instant and cannot black the preview out.
    ///
    /// Opens on `.cameraOnMain` because before the first swing there is nothing to put on the
    /// other surface; the take's first replay adopts the Settings default.
    ///
    /// Observed rather than re-applied by hand at each write site, so no future assignment can
    /// forget to reconsider the pose subscription — a mode the skeleton disagrees with is 30
    /// main-actor writes a second feeding an overlay nobody can see.
    private(set) var displayMode: CaptureDisplayMode = .cameraOnMain {
        didSet {
            guard oldValue != displayMode else { return }
            applySkeletonSubscription()
        }
    }

    // MARK: - Dependencies

    var modelContext: ModelContext?

    // MARK: - Collaborators

    let cameraService = CameraService.shared
    private let detectionOrchestrator = DetectionOrchestrator()
    private let videoStorageService = VideoStorageService.shared

    private var countdownTask: Task<Void, Never>?
    private var finalizeWatchdog: Task<Void, Never>?
    private var replayTask: Task<Void, Never>?

    /// File abandoned by `cancel()`. `AVCaptureMovieFileOutput` keeps writing after
    /// `stopRecording()` returns, so the file cannot be deleted inline without racing the
    /// writer — it is removed once the delegate reports the write finished.
    private var urlPendingDiscard: URL?

    /// Generous: a long recording's `AVCaptureMovieFileOutput` finalize plus the copy into
    /// app storage can legitimately take a while on an older device.
    private static let finalizeTimeout: TimeInterval = 20

    /// How long the countdown waits for the capture session before giving up. A first
    /// launch on device measured 7.2 s to configure plus 15.5 s inside `startRunning`
    /// while StoreKit and CoreML competed for the same window — an unbounded wait parks
    /// the countdown on a black screen with no way out. 8 s clears a healthy cold start
    /// with room to spare and turns a pathological one into a retry prompt.
    private static let sessionStartTimeout: TimeInterval = 8

    /// **Ceiling on the whole wait between a detected swing and its replay, and the number the
    /// progress bar is drawn against.** A clip runs a second past impact while detection
    /// concludes only a few frames after it, so the follow-through has not been captured yet
    /// when the swing is reported. The wait is normally ~1.0 s — this bounds it for a clip whose
    /// impact estimate landed far enough back to ask for an implausible one.
    ///
    /// 1.5 s is a ceiling, not a target, and nothing here manufactures delay to reach it: the
    /// replay is presented the instant its frames are ready.
    private static let maximumReplayTail: TimeInterval = 1.5

    /// The slice of that ceiling set aside for the encoder, on top of the part of the clip that
    /// has not happened yet.
    ///
    /// The scale and the JPEG encode moved off the capture queue (`CapturedFrameRelay`), which is
    /// what let the replay's resolution rise to the camera's own — and it means a frame is in the
    /// ring some milliseconds AFTER it was captured. It is spent only if the ring is genuinely still
    /// catching up.
    ///
    /// 300ms, raised with the resolution, and derived from the relay rather than picked: a frame is
    /// delivered at most one encode after the frames in front of it are, so the worst case is the
    /// pool's four slots drained by two workers at the 133ms each is budgeted — two rounds, ~266ms.
    /// The whole wait therefore lands at `tail + 0.3` ≈ 1.3s for a swing detected near impact, which
    /// is inside the 1.5s `maximumReplayTail` ceiling and inside what the owner accepted. Past that
    /// the deadline fires and the pull comes back partial, which is a replay missing its last frame
    /// or two rather than a screen that waits.
    private static let encodeAllowance: TimeInterval = 0.3

    /// Floor on the whole wait, below which no bar is drawn at all. A bar that appears and vanishes
    /// inside a few frames is a flash, not information.
    ///
    /// Read against the wait INCLUDING `encodeAllowance`, so 0.4 s here means a clip with less than
    /// 0.2 s of tail left — detection reporting the swing long after impact — goes straight to the
    /// replay. Not the normal case and not meant to be: the clip ends at `impact + 1.0`, so a swing
    /// detected anywhere near impact waits ~1 s and gets the bar the user asked for.
    private static let minimumSettle: TimeInterval = 0.4

    /// How often the ring is asked whether it has caught up. Well inside one sampled frame period
    /// (66.7ms), so readiness is noticed in the tick it happens, and cheap: one lock and one
    /// comparison, on a screen that is showing a progress bar and nothing else.
    private static let readinessPollInterval = Duration.milliseconds(20)

    // MARK: - Computed Properties

    var isCountingDown: Bool { if case .countdown = state { return true }; return false }
    var countdownValue: Int { if case .countdown(let v) = state { return v }; return 0 }
    var isRecording: Bool { state == .recording }
    var isFinalizingVideo: Bool { state == .finalizingVideo }
    var isSaving: Bool { state == .saving }
    var isReviewing: Bool { state == .reviewing }
    var swingCount: Int { detectedSwings.count }
    var isFrontCamera: Bool { cameraService.currentCameraPosition == .front }

    /// The replay both surfaces draw from, or nil when the screen has only one thing on it.
    /// The tile, the full-screen cover and the swap all derive from THIS single property
    /// rather than re-deriving the same conjunction, so they cannot end up disagreeing about
    /// what is on screen.
    ///
    /// `isRecording` is what binds it to the ring buffer's lifetime. The ring is armed by
    /// `CameraService.startRecording()` and dropped by `stopRecording()` — so a replay exists
    /// only while the live frames feeding the OTHER surface do, and neither mode can ever be
    /// asked to draw a camera that has no frames.
    var activeReplay: SwingReplay? { isRecording ? swingReplay : nil }

    /// The replay is covering the preview. The skeleton overlay reads this too: those joints
    /// belong to the frame arriving now, and drawing them over a replay of a moment that has
    /// already happened would put the golfer's skeleton somewhere the golfer isn't.
    var isReplayOnMain: Bool { activeReplay != nil && displayMode == .swingOnMain }

    /// Whether a skeleton is going to be drawn at all — the toggle AND a screen to draw it on.
    /// `applySkeletonSubscription()` is the only reason this exists: the cost of a skeleton is
    /// not the drawing, it is a main-actor write per frame invalidating the view body ~30 times
    /// a second, and paying that for a hidden overlay is what the default mode used to do.
    var drawsSkeleton: Bool { isSkeletonEnabled && !isReplayOnMain }

    /// Whether the shared camera is carrying nothing for this instance: no take being
    /// captured, no file being written, no copy into the library in progress — so handing
    /// the camera back costs no work.
    ///
    /// `.reviewing` counts. That recording is a finished file on disk, and the only things
    /// that act on it are this screen's own Save and Delete; the camera is no part of
    /// either. Reading `.reviewing` as "walking away is an answer" is what let a tab change
    /// delete the user's take.
    private var holdsNoCameraWork: Bool {
        switch state {
        case .idle, .reviewing: return true
        case .countdown, .recording, .finalizingVideo, .saving, .saved: return false
        }
    }

    /// Every route into `.reviewing` owes the user an explanation, and the ones that arrive
    /// there by recovery (save blocked, watchdog, persistence failed) never set a specific one.
    var currentReviewNotice: ReviewNotice { reviewNotice ?? .manualReview }

    // MARK: - Init

    init() {
        detectionOrchestrator.onSwingDetected = { [weak self] clip in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.detectedSwings.append(clip)
                self.playbackSpeed = 1.0
                #if DEBUG
                let coverage = self.cameraService.swingFrameBuffer.coverage()
                DeviceProbe.event("swing_detected", [
                    "index": String(self.detectedSwings.count),
                    "confidence": String(format: "%.2f", clip.confidence),
                    // The tile is fed from the in-memory ring, so "no replay appeared" is
                    // answered by these three: what the clip asks for, and what the ring was
                    // actually holding when it asked. The outcome lands separately in
                    // `swing_replay`, which cannot be known yet — the tail of this clip has
                    // not been captured at this point. Both lines carry `index`, so they join.
                    "clip_s": Self.rangeLabel(clip.startTime, clip.endTime),
                    "buffered_frames": String(coverage.count),
                    "buffered_s": Self.rangeLabel(coverage.oldest, coverage.newest),
                    // MEASURED, and the pair to `buffered_s`: whether the ring's window was
                    // shortened by the byte ceiling rather than by time, and what the frames
                    // actually cost on this device — the estimate the resolution was chosen against.
                    "buffered_kb": String(coverage.bytes / 1024),
                    "sheds": String(coverage.sheds)
                ])
                #endif
                Analytics.shared.track(.swingDetected)
                // Immediate feedback — haptic + green flash + swing-count badge in the top
                // bar — while the replay tile follows a beat later, once the swing it is
                // going to show has finished happening. We do NOT play the in-progress
                // recording file: opening it with AVURLAsset causes iOS to terminate the
                // recording (FigApplicationStateMonitor interrupt).
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.loadReplay(of: clip, number: self.detectedSwings.count)
            }
        }
    }

    /// Only this instance's own collaborator is torn down here. `cameraService` is a
    /// shared singleton and MUST NOT be touched from `deinit`: SwiftUI evaluates the
    /// `@State private var viewModel = RecordingViewModel()` default-value expression on
    /// every construction of the enclosing view struct — which `MainTabView` does on every
    /// tab switch — and discards all but the first instance. A `deinit` that cleared the
    /// singleton's callbacks therefore wiped the *live* view model's `onRecordingFinished`,
    /// leaving the app stuck on the finalizing overlay forever. Ownership of the shared
    /// callbacks now lives in `activate()` / `deactivate()`, driven by the view's lifecycle.
    deinit {
        detectionOrchestrator.onSwingDetected = nil
    }

    // MARK: - Shared-Camera Ownership

    /// Claim the shared camera's callbacks. Called from the view's `onAppear`, so a
    /// throwaway instance that is never installed in the view tree never claims them.
    func activate() {
        // Registration, not construction: this is the one moment the INSTALLED instance
        // claims the shared camera, so it is the only honest definition of "the live view
        // model". The identity prop makes a second live instance — the throwaway-view-model
        // bug that nil'd the singleton's callbacks — a fact in the timeline, not a deduction.
        #if DEBUG
        DebugScenario.shared.attach(self)
        DeviceProbe.event("recording_vm_activated", [
            "instance": DeviceProbe.identity(self),
            "state": state.probeLabel
        ])
        #endif
        applySkeletonSubscription()
        cameraService.onMaximumRecordingDurationReached = { [weak self] in
            self?.stopRecording()
        }
        // The ring's memory valve, fanned out to the one object that can finish the job. The ring can
        // empty itself; it cannot free the frames a replay is holding, because what it handed over
        // was a retain on the same `Data`.
        //
        // Claimed HERE and not in `init`, for the reason every other shared-camera callback is: a
        // throwaway view model — SwiftUI builds one per construction of the enclosing view and
        // discards all but the first — would take the valve away from the live instance and hand it to
        // an object with no replay to drop. That is the failure class that once stranded this screen
        // on the finalizing overlay.
        cameraService.swingFrameBuffer.onShed = { [weak self] in
            Task { @MainActor [weak self] in
                self?.abandonReplayUnderMemoryPressure()
            }
        }
        cameraService.onRecordingFinished = { [weak self] url, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // A cancelled recording still finishes writing and still lands here. Discard the
                // file rather than processing it — previously `cancel()` nil'd `recordingURL`
                // before the write completed, so nothing ever deleted it and every cancel
                // during recording leaked a temp .mov.
                //
                // Matched on URL IDENTITY, not merely on the flag being set. If the flag ever
                // went stale (stopRecording() is a no-op when the movie output wasn't actually
                // recording, so no delegate callback arrives to consume it), a set-flag test
                // would throw away the NEXT perfectly good recording. Identity makes that
                // impossible by construction.
                if let pending = self.urlPendingDiscard {
                    self.urlPendingDiscard = nil
                    if url == nil || url == pending {
                        try? FileManager.default.removeItem(at: pending)
                        if let url, url != pending {
                            try? FileManager.default.removeItem(at: url)
                        }
                        AppLogger.camera.info("RecordingViewModel: discarded cancelled recording")
                        return
                    }
                    // Different file: this is a legitimate recording. Drop the stale flag and
                    // fall through to normal handling.
                    AppLogger.camera.info("RecordingViewModel: dropped stale discard flag")
                }

                // Any delivery for a file that is not the current recording is stale — e.g. a
                // cancelled recording whose finalize outlived `beginRecording()` clearing the
                // discard flag. Processing it (either branch below) would pause the live
                // session and delete or reset the in-flight recording, so remove the orphan
                // and leave the state machine untouched.
                if let url, url != self.recordingURL {
                    try? FileManager.default.removeItem(at: url)
                    AppLogger.camera.info("RecordingViewModel: ignored stale recording delivery")
                    return
                }

                // Once the finalize watchdog has recovered into `.reviewing`, the manual
                // Save/Delete path owns this recording. A merely-slow callback arriving after
                // that must not re-enter the save pipeline (a duplicate library entry) or
                // clobber the recovered state. `.recording` stays accepted: a spontaneous
                // stop (interruption, disk full) delivers without `stopRecording()` running.
                guard self.state == .recording || self.state == .finalizingVideo else {
                    AppLogger.camera.info("RecordingViewModel: late recording delivery after watchdog recovery — ignoring")
                    return
                }

                // AVFoundation routinely "fails" with AVErrorRecordingSuccessfullyFinishedKey
                // set (max duration, disk full, interruption) and a fully playable file —
                // that is a completed recording, not a failure.
                let finishedCleanly = error.map {
                    (($0 as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
                } ?? true

                if let error, !finishedCleanly || url == nil {
                    AppLogger.camera.error("RecordingViewModel: onRecordingFinished error=\(error.localizedDescription)")
                    if let url { try? FileManager.default.removeItem(at: url) }
                    self.errorMessage = error.localizedDescription
                    self.detectionOrchestrator.stop()
                    self.cameraService.onFrameCaptured = nil
                    self.cameraService.onAudioCaptured = nil
                    self.recordingURL = nil
                    self.state = .idle
                } else {
                    if let error {
                        AppLogger.camera.info("RecordingViewModel: recording finished cleanly despite error: \(error.localizedDescription)")
                    }
                    #if DEBUG
                    DeviceProbe.event("recording_finalized", [
                        "instance": DeviceProbe.identity(self),
                        "swings": String(self.detectedSwings.count)
                    ])
                    #endif
                    self.cameraService.pauseSession()
                    await self.handleRecordingFinished()
                }
            }
        }
    }

    /// The Camera tab's exit handler. Keyed off the tab selection rather than `onDisappear`,
    /// which also fires when the view merely PRESENTS the library-upgrade paywall — tearing
    /// down then deleted the recording the user was being asked to pay to keep. The guard
    /// keeps that promise even now that the paywall no longer moves the tab.
    ///
    /// Every branch below exists because the tab bar is reachable at every point of a take
    /// now that the capture UI is no longer a full-screen cover. What leaving means depends
    /// on what the take is doing, and none of the answers is "destroy it".
    func handleCameraTabLeft() {
        guard !requiresLibraryUpgrade else { return }
        // A countdown is not a take yet, and letting it finish would start a recording on a
        // tab the user has already left. Dropping it lands in `.idle`, so the release below
        // still runs.
        abortCountdown()
        switch state {
        case .recording:
            // The Stop control leaves with the tab: the only terminator left would be the
            // 30-minute cap, with camera, mic and the green indicator running the whole way
            // and no timer anywhere in the app. The user recorded this — take the normal
            // finalize→save route instead of abandoning it. The camera is released when
            // that route lands, off-tab (`RecordingView.handleStateChange`).
            stopRecording()
        case .reviewing:
            // Already on disk, waiting for a Save or Delete the user has not given yet.
            // Keep the take and hand the camera back; returning to the tab picks the review
            // up exactly where it was. This is the branch that used to delete the file —
            // both from a detection miss and from the trip to History the library gate had
            // just asked the user to make.
            releaseCamera()
        case .idle:
            discardTake()
            releaseCamera()
        case .countdown, .finalizingVideo, .saving, .saved:
            // Work in flight owns the camera. Letting go here would abandon a file
            // mid-write or a copy mid-flight; the release happens when the work lands.
            break
        }
    }

    /// Hand the shared camera back: stop the session, then drop this instance's claim on its
    /// callbacks. For when the Camera tab is no longer the user's screen — a session left
    /// running under another tab lights the green privacy indicator and holds the
    /// `.playAndRecord` audio route, and callbacks held from another tab are how a stale
    /// instance ate the live one's recording.
    ///
    /// Destroys nothing: a take waiting in `.reviewing` keeps its file and its state, and
    /// `activate()` reclaims the callbacks on the next appear. Refuses while the camera is
    /// carrying work, so the caller can call it early and again when that work lands.
    func releaseCamera() {
        guard holdsNoCameraWork else { return }
        cameraService.stopSession()
        deactivate()
    }

    /// Hand-off after the copy into app storage: the persistence result decides the terminal
    /// state. A nil `savedVideo` means the take never reached the library — claiming `.saved`
    /// would hide it from History with no error and no retry path.
    func completePersistence(savedVideo: SwingVideo?, originalURL: URL) {
        cancelFinalizeWatchdog()
        guard let savedVideo else {
            #if DEBUG
            DeviceProbe.event("save_failed", ["reason": "persistence_returned_nil"], ui: true)
            #endif
            errorMessage = String(localized: "Couldn't add this recording to your library. Tap Save to try again.", comment: "Error shown when copying a finished recording into the in-app library failed; the user retries with the Save button on the capture review panel")
            state = .reviewing
            return
        }
        finalizeSave(with: savedVideo, originalURL: originalURL)
    }

    /// Abandon an in-flight countdown. Without this, leaving the tab mid-countdown let the
    /// countdown run to completion and call `beginRecording()` against the session that
    /// `handleDisappear` had just paused, surfacing a spurious
    /// "Camera session is not running." alert.
    func abortCountdown() {
        guard isCountingDown else { return }
        countdownTask?.cancel()
        countdownTask = nil
        state = .idle
    }

    /// Subscribes to (or unsubscribes from) per-frame skeletons. `onPoseDetected` is this
    /// instance's own orchestrator, not the shared camera, so it is safe to touch any time.
    ///
    /// Idempotent, because every input to `drawsSkeleton` re-applies it: the toggle's `didSet`,
    /// the mode's, the replay's, and `activate()`.
    private func applySkeletonSubscription() {
        guard drawsSkeleton else {
            detectionOrchestrator.onPoseDetected = nil
            clearSkeleton()
            return
        }
        detectionOrchestrator.onPoseDetected = { [weak self] jointMap in
            self?.latestJointMap = jointMap
        }
    }

    /// Drops the last skeleton whenever the subscription goes away, so a swap back to the
    /// camera cannot flash the pose the golfer was in when it was cut. Guarded: this runs on
    /// every mode change, and an unguarded write to an @Observable property invalidates every
    /// view reading it whether or not the value actually changed.
    private func clearSkeleton() {
        guard latestJointMap != nil else { return }
        latestJointMap = nil
    }

    /// Release the shared camera's callbacks. Only safe once the camera carries no work —
    /// during a countdown, a recording, or the finalize/save hand-off they are load-bearing,
    /// and `onDisappear` also fires when this view merely presents a sheet or paywall.
    ///
    /// `.reviewing` qualifies: that recording is finished, so nothing is owed to
    /// `onRecordingFinished` any more — a late delivery after a watchdog recovery was
    /// already being dropped by its own state guard. `recordingURL` is deliberately left
    /// alone; the take is the user's until they say otherwise.
    func deactivate() {
        // Clearing `onRecordingFinished` is what once stranded the app on the finalizing
        // overlay forever, so every release is recorded with the identity doing it.
        #if DEBUG
        DeviceProbe.event("recording_vm_deactivated", [
            "instance": DeviceProbe.identity(self),
            "state": state.probeLabel,
            "released": String(holdsNoCameraWork)
        ])
        #endif
        guard holdsNoCameraWork else { return }

        // We are about to drop onRecordingFinished, which is what consumes a deferred discard.
        // Anything still pending would never be cleaned up, so delete it now. (Identity matching
        // in the handler already prevents a stale flag from destroying a LATER recording — this
        // closes the remaining file leak, not a correctness hole.) Unlinking a file the writer
        // may still hold is safe: the data is freed when it closes its descriptor.
        if let pending = urlPendingDiscard {
            urlPendingDiscard = nil
            try? FileManager.default.removeItem(at: pending)
        }

        detectionOrchestrator.onPoseDetected = nil
        clearSkeleton()
        cameraService.onRecordingFinished = nil
        cameraService.onFrameCaptured = nil
        cameraService.onAudioCaptured = nil
        cameraService.onMaximumRecordingDurationReached = nil
        // Released with the rest of them: this instance is no longer the one holding a replay, so it
        // is no longer the one that should be told to let one go.
        cameraService.swingFrameBuffer.onShed = nil
    }

    /// Auto-save flow after a recording finishes. No swings detected → hand the take back
    /// to the user. Swings detected → save into the app's own library directly, skipping the
    /// manual Delete/Save Review step. The FinalizingVideoOverlay stays visible
    /// continuously from .finalizingVideo through .saving to .saved, so there
    /// is no UI flash mid-flow.
    private func handleRecordingFinished() async {
        guard !detectedSwings.isEmpty else {
            presentNoSwingReview()
            return
        }
        await saveRecording()
        // saveRecording sets state .saving as soon as preconditions pass. If
        // state is still .finalizingVideo here, the save was blocked (library
        // gate / paywall) — drop into .reviewing so the user has a manual
        // Save/Delete fallback once they dismiss the paywall.
        if state == .finalizingVideo {
            state = .reviewing
        }
    }

    /// The take holds no detected swing. This used to delete the file on the spot — one
    /// line after an overlay promising "Saving Video..." and one line after the session was
    /// paused — so the user was left facing a black screen with their clip gone and nothing
    /// said about it. Detection misses real swings often enough (framing, light, a practice
    /// swing) that the call belongs to the user: `.reviewing` already offers Save and
    /// Delete, and the take is stored whole either way — markers are all a swing adds.
    private func presentNoSwingReview() {
        cancelFinalizeWatchdog()
        AppLogger.camera.info("RecordingViewModel: no swings detected — offering the take for review")
        #if DEBUG
        DeviceProbe.event("no_swings_review", [
            "duration_s": String(format: "%.1f", cameraService.recordedDuration)
        ], ui: true)
        #endif
        Analytics.shared.track(.recordingNoSwingsDetected(duration: cameraService.recordedDuration))
        reviewNotice = .noSwingDetected
        state = .reviewing
    }

    // MARK: - Swing Replay

    /// Puts the swing on screen in two steps: the WAIT first, said out loud, and then the frames.
    ///
    /// The wait is the whole point, and it is unavoidable. A clip ends a second past impact and
    /// detection reports it a few frames after impact, so pulling on the spot would hand over a
    /// replay that stops dead at the ball — no follow-through, which is half of what a golfer
    /// wants to see. `detectionTime` is the heuristic's own peak-velocity timestamp and so is
    /// never later than the frame being processed, which makes this difference an over-estimate:
    /// the tail is always fully captured by the time we ask for it.
    ///
    /// What changed is that the golfer is no longer left looking at nothing for that second. The
    /// replay is published IMMEDIATELY, empty, carrying the wait's real start and real length —
    /// which is what turns both capture surfaces black with a filling white bar, on every
    /// detection, and what makes the bar's progress a fact rather than an animation.
    private func loadReplay(of clip: SwingClip, number: Int) {
        // A newer swing supersedes an older one still waiting for its tail — including one still
        // inside its wait, whose surface is handed straight over to the new swing's bar.
        replayTask?.cancel()
        // ONE description of the wait, shared by the bar that draws it and the task that serves
        // it. Two clocks read a few milliseconds apart would let the bar finish before the
        // picture arrived, which is the one thing a progress bar must never do.
        let wait = Self.plannedWait(for: clip)
        presentLoading(of: clip, number: number, during: wait)
        replayTask = Task { [weak self] in
            await self?.presentWhenReady(clip, number: number, during: wait)
        }
    }

    /// How long the golfer is going to wait, and therefore how long the bar has to fill: the part
    /// of the clip that has not happened yet, plus the encoder's allowance, under the ceiling.
    private static func plannedWait(for clip: SwingClip) -> SwingReplay.Loading {
        let tail = max(0, clip.endTime - clip.detectionTime)
        return SwingReplay.Loading(
            startedAt: ProcessInfo.processInfo.systemUptime,
            duration: min(maximumReplayTail, tail + encodeAllowance)
        )
    }

    /// The black screen and the white bar. An empty `SwingReplay` — `activeReplay` becomes
    /// non-nil here, which is what mounts both surfaces, so nothing in the view layer had to
    /// learn a third state.
    ///
    /// Skipped entirely for a wait too short to read, in which case the take's first replay
    /// adopts the default mode a moment later, when the frames land.
    private func presentLoading(of clip: SwingClip, number: Int, during wait: SwingReplay.Loading) {
        guard wait.duration >= Self.minimumSettle else { return }
        adoptDefaultModeIfFirstReplay()
        swingReplay = SwingReplay(id: clip.id, number: number, frames: [], loading: wait)
    }

    /// Sleeps out the part of the clip that has not been captured, then waits for the ring to
    /// finish encoding it — no longer than the wait the bar is drawn against.
    private func presentWhenReady(_ clip: SwingClip, number: Int, during wait: SwingReplay.Loading) async {
        let tail = min(Self.maximumReplayTail, max(0, clip.endTime - clip.detectionTime))
        try? await Task.sleep(for: .seconds(tail))
        let ready = await awaitEncodedFrames(through: clip.endTime, until: wait.startedAt + wait.duration)
        guard !Task.isCancelled, isRecording else { return }
        presentReplay(of: clip, number: number, ready: ready, waited: wait.elapsed)
    }

    /// Polls the ring until it holds the whole range, and gives up at the deadline rather than
    /// hanging — a replay a frame or two short of its follow-through is worth having, and a
    /// screen that waits forever is not. A take that ends mid-wait exits through the
    /// `isRecording` guard above.
    ///
    /// Deliberately unbothered that the ring's time origin and the detector's can differ by the
    /// frames that landed between the two latches: the ring's is never LATER, so this can only
    /// report ready marginally EARLY — the same signed skew `frames(from:to:)` already lives with.
    private func awaitEncodedFrames(through end: TimeInterval, until deadline: TimeInterval) async -> Bool {
        let buffer = cameraService.swingFrameBuffer
        while ProcessInfo.processInfo.systemUptime < deadline {
            if buffer.hasFrames(through: end) { return true }
            try? await Task.sleep(for: Self.readinessPollInterval)
            guard !Task.isCancelled else { return false }
        }
        return buffer.hasFrames(through: end)
    }

    /// The frames, at last. `ready` and `waited_ms` are what make the next device run answerable:
    /// a replay that came out short is either a range that aged out or an encoder that never
    /// caught up, and those two have different fixes.
    private func presentReplay(of clip: SwingClip, number: Int, ready: Bool, waited: TimeInterval) {
        let frames = cameraService.swingFrameBuffer.frames(from: clip.startTime, to: clip.endTime)
        adopt(frames, of: clip, number: number)
        #if DEBUG
        DeviceProbe.event("swing_replay", [
            "index": String(number),
            "frames": String(frames.count),
            "clip_s": Self.rangeLabel(clip.startTime, clip.endTime),
            "shown": String(!frames.isEmpty),
            // Whether the ring had encoded the whole range, and how long the golfer waited for
            // it. Together with `ring_encode`'s depth and drops they say whether the wait was the
            // clip's tail or the encoder's backlog.
            "ready": String(ready),
            "waited_ms": String(format: "%.0f", waited * 1000),
            // Which surface it landed on. Every change the user makes afterwards arrives as
            // its own `pip_swapped` line, so the two together say what was on screen and when.
            "mode": displayMode.probeLabel,
            // Read AFTER `adopt`, so for an empty pull it separates the two outcomes that used to be
            // one: the loading surface came down (nothing on screen), or a previous swing was left
            // playing untouched.
            "kept_playing": String(frames.isEmpty && swingReplay != nil)
        ])
        #endif
    }

    /// An empty pull means the range aged out of the ring, was shed under memory pressure, or was
    /// never encoded at all.
    ///
    /// A loading surface is dropped rather than left behind: the screen is black with a bar that has
    /// finished filling, and leaving that up is the worst of the available outcomes. **But only a
    /// LOADING surface**, which is the correction — an unconditional teardown nil'd `swingReplay` and
    /// put `displayMode` back to `.cameraOnMain`, so a new swing whose pull came back empty took away
    /// the replay the golfer was watching and the surface they had chosen for it, for a swing they
    /// never even saw. See `abandonLoadingSurface`.
    private func adopt(_ frames: [Data], of clip: SwingClip, number: Int) {
        guard !frames.isEmpty else {
            abandonLoadingSurface()
            return
        }
        adoptDefaultModeIfFirstReplay()
        swingReplay = SwingReplay(id: clip.id, number: number, frames: frames)
    }

    /// Takes down a wait that is never going to end, and only that.
    ///
    /// **The test is emptiness, and deliberately NOT identity.** A replay carrying frames is a picture
    /// somebody is watching and is left alone — that is the whole correction. But an EMPTY one on
    /// screen is a black surface with a bar on it, and it is dishonest whichever swing raised it: the
    /// only task that could ever have filled it is `replayTask`, and `loadReplay` cancels that the
    /// moment a newer swing arrives. So a bar left over from a superseded swing — reachable when the
    /// newer swing's wait was too short for `presentLoading` to replace it — has exactly as little
    /// behind it as this swing's own, and comes down for the same reason.
    ///
    /// Nil is nothing to do: the wait was too short to draw a bar for, so no surface was ever raised.
    ///
    /// The asymmetry with the memory-pressure path is deliberate and the two are not in conflict.
    /// There, `clearReplay()` resets the mode as well, because a shed leaves NOTHING that could be on
    /// the main surface. Here something may still be playing, and then the mode is the user's and
    /// stays theirs.
    private func abandonLoadingSurface() {
        guard swingReplay?.frames.isEmpty == true else { return }
        clearReplay()
    }

    /// The ring has given its frames back under system memory pressure, so the replay holding a retain
    /// on them goes too.
    ///
    /// **Losing a replay here is the design, not a regression.** `SwingFrameBuffer.shed` exists so the
    /// app is not jetsammed while AVFoundation is writing the movie file, and it cannot deliver that
    /// alone: `frames(from:to:)` hands out refcounted `Data`, and `swingReplay` keeps its share alive
    /// for as long as it is published. Under real pressure that is most of what there was to give
    /// back — the ring's own copy plus, through the surface unmounting, up to ~25MB of decoded
    /// bitmaps.
    ///
    /// `clearReplay()` and nothing gentler, because every softer answer is dishonest. A replay still
    /// inside its wait would sit on a black surface whose bar fills to the end and never becomes a
    /// picture; a replay already playing would keep holding the very megabytes the system just asked
    /// for. Both surfaces unmount, the permanently-mounted preview is uncovered, and the next swing
    /// re-reads the default mode.
    private func abandonReplayUnderMemoryPressure() {
        guard let replay = swingReplay else { return }
        #if DEBUG
        DeviceProbe.event("replay_shed", [
            "index": String(replay.number),
            "frames": String(replay.frames.count),
            // Which of the two dishonest surfaces this event prevented: a bar that would never have
            // become a picture, or a loop that would have gone on holding the frames.
            "was_loading": String(replay.loading != nil),
            "mode": displayMode.probeLabel
        ], ui: true)
        #endif
        AppLogger.camera.warning("RecordingViewModel: dropped swing replay \(replay.number) under memory pressure — the recording continues")
        clearReplay()
    }

    /// The take's first replay adopts the Settings default; every later swing leaves the mode
    /// exactly where the user put it and changes only the CONTENT. Swapping the screen under
    /// someone's thumb seconds after they chose it is the app arguing with them — and swings
    /// arrive in bursts, so it would happen repeatedly.
    ///
    /// "First" is `swingReplay == nil`, which `clearReplay()` establishes at the start of every
    /// take. It is now read when the swing is DETECTED rather than when its frames land, because
    /// the wait is drawn on whichever surface the preference chooses — and a first swing that
    /// ends up with no frames at all puts `swingReplay` back to nil through `clearReplay()`, so
    /// the take's one chance to read the preference is returned rather than spent.
    private func adoptDefaultModeIfFirstReplay() {
        guard swingReplay == nil else { return }
        displayMode = .storedDefault
    }

    /// Drops the tile and any replay still waiting for its tail. Called wherever a take
    /// begins or ends: the frames are the previous swing's and nothing on screen should
    /// outlive it — least of all a couple of megabytes of them. And from
    /// `abandonReplayUnderMemoryPressure`, where those megabytes are the whole reason.
    private func clearReplay() {
        replayTask?.cancel()
        replayTask = nil
        swingReplay = nil
        // Back to the uncovered preview, and back to "no mode chosen yet" — a swap made
        // during this take must not become the next take's opening mode. The next first
        // swing re-reads the preference.
        displayMode = .cameraOnMain
    }

    /// The picture-in-picture tile's tap: the swing and the camera trade surfaces.
    ///
    /// A no-op when there is nothing to trade with, so the mode can never describe a screen
    /// that has only one thing on it. All this does is flip a flag — the view layer changes
    /// what it draws OVER the permanently-mounted preview, and no capture object is touched.
    func swapDisplaySurfaces() {
        guard activeReplay != nil else { return }
        let previous = displayMode
        displayMode = previous.swapped
        #if DEBUG
        DeviceProbe.event("pip_swapped", [
            "from": previous.probeLabel,
            "to": displayMode.probeLabel,
            "index": String(swingReplay?.number ?? 0)
        ], ui: true)
        #endif
    }

    #if DEBUG
    private static func rangeLabel(_ from: TimeInterval?, _ to: TimeInterval?) -> String {
        guard let from, let to else { return "none" }
        return String(format: "%.2f-%.2f", from, to)
    }
    #endif

    // MARK: - Actions

    func startRecording() {
        // Recorded BEFORE the guard: "Start Recording did nothing" is a real report, and the
        // no-op branch is the answer to it.
        #if DEBUG
        DeviceProbe.event("record_tapped", [
            "state": state.probeLabel,
            "accepted": String(state == .idle),
            "session_running": String(cameraService.isSessionRunning)
        ], ui: true, frame: true)
        #endif
        guard state == .idle else { return }
        // Kicked here, not from `App.init` or `activate()`: at launch the CoreML
        // specialization competed with the camera's own cold bring-up for the CPU and the
        // ANE, and on device the model finished loading AFTER `startRunning` returned — it
        // had lengthened exactly the window it was meant to avoid. `activate()` now runs on
        // tab appear, alongside that same bring-up. A full countdown runs from here before
        // `detectionOrchestrator.start()` needs a model, so this is the last quiet moment.
        SwingClassifier.warmUp()
        // Same moment, same argument. The replay ring's encoder builds a CoreImage context and
        // specializes JPEG kernels on its first frame; paid during the take instead, that stall is
        // the encoder's pool filling and dropping frames, and it would put a false "the resolution
        // is too high" reading into every first take's `ring_encode`.
        cameraService.swingFrameBuffer.warmUp()
        countdownTask?.cancel()
        // A skeleton left over from the previous take would be redrawn frozen over the
        // countdown — fresh poses only start arriving once recording begins.
        latestJointMap = nil
        state = .countdown(remaining: 5)

        countdownTask = Task {
            let started = await ensureSessionRunning()
            guard !Task.isCancelled else { return }
            guard started else {
                #if DEBUG
                DeviceProbe.event("countdown_aborted", ["reason": "session_never_started"], ui: true, frame: true)
                #endif
                state = .idle
                errorMessage = String(localized: "Camera could not start. Tap Start Recording to try again.", comment: "Error message shown when the capture session fails to start during the recording countdown; a retry from the same screen usually succeeds")
                return
            }

            for i in stride(from: 5, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                state = .countdown(remaining: i)
                #if DEBUG
                DeviceProbe.event("countdown_tick", ["remaining": String(i)])
                #endif
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }

            beginRecording()
        }
    }

    /// Bring the session up entirely on the camera's session queue and return once it is
    /// actually running. Nothing here reads `captureSession`: a main-actor read serializes
    /// against an in-flight configuration on the session queue, which is the
    /// first-cold-launch freeze itself. The answer comes from the bring-up's own result.
    ///
    /// Bounded, because the bring-up can take 22 s on a cold first launch and an unbounded
    /// await leaves the countdown frozen with no way out. Losing the race abandons the
    /// *wait*, not the work: `prepareAndStartSession` suspends on a continuation only the
    /// session queue resumes, so cancelling it does nothing — which is also why a
    /// `withTaskGroup` race cannot express this. A group waits for every child before it
    /// returns, so the slow child would still be waited on.
    private func ensureSessionRunning() async -> Bool {
        let slot = SessionStartSlot()
        Task { [cameraService] in
            slot.record(await cameraService.prepareAndStartSession(position: .front, frameRate: 30))
        }
        return await waitForSessionStart(slot)
    }

    /// Polls the bring-up's own result slot — a main-written value, never the session.
    /// A fresh slot per attempt, so a bring-up we stopped waiting on cannot answer for a
    /// later one.
    private func waitForSessionStart(_ slot: SessionStartSlot) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(Self.sessionStartTimeout))
        while ContinuousClock.now < deadline {
            if let started = slot.started { return started }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return false }
        }
        AppLogger.camera.error("RecordingViewModel: camera bring-up exceeded \(Self.sessionStartTimeout)s — abandoning the wait")
        #if DEBUG
        DeviceProbe.event("session_wait_abandoned", ["timeout_s": String(Int(Self.sessionStartTimeout))])
        #endif
        return false
    }

    private func beginRecording() {
        // An interruption (call banner, FaceTime PiP, Split View) leaves `isSessionRunning`
        // true while the session delivers no frames. The InterruptionOverlay is already up,
        // so abort silently rather than stacking an error alert on top of it.
        guard !cameraService.isInterrupted else {
            #if DEBUG
            DeviceProbe.event("recording_start_aborted", ["reason": "session_interrupted"], ui: true)
            #endif
            state = .idle
            return
        }
        // The @Observable mirror is main-written and never touches the session object;
        // reading `captureSession` state here would block the main thread against
        // sessionQueue. `prepareAndStartSession` set the mirror before the countdown ran,
        // and pauses (background) clear it — interruptions do not, hence the separate
        // `isInterrupted` check above — so it is current enough to catch "the session
        // died mid-countdown".
        guard cameraService.isSessionRunning else {
            #if DEBUG
            DeviceProbe.event("recording_start_aborted", ["reason": "session_not_running"], ui: true, frame: true)
            #endif
            state = .idle
            errorMessage = String(localized: "Camera session is not running.", comment: "Error message when the user taps record but the AVCaptureSession is not active")
            return
        }
        guard let url = cameraService.startRecording() else {
            #if DEBUG
            DeviceProbe.event("recording_start_aborted", [
                "reason": "no_output_url",
                "error": cameraService.currentError?.errorDescription ?? "none"
            ], ui: true)
            #endif
            state = .idle
            errorMessage = cameraService.currentError?.errorDescription
            return
        }

        recordingURL = url
        // Clear any stale discard flag. If a previous cancel() set it but the delegate never
        // fired (stopRecording() is a no-op when the movie output wasn't actually recording),
        // the flag would survive and cause THIS perfectly good recording to be thrown away.
        urlPendingDiscard = nil
        detectedSwings.removeAll()
        clearReplay()
        // The previous take's explanation must not survive into this one's review.
        reviewNotice = nil
        state = .recording
        #if DEBUG
        DeviceProbe.event("recording_started", ["file": url.lastPathComponent], ui: true, frame: true)
        #endif
        Analytics.shared.track(.recordingStarted)
        cameraService.onFrameCaptured = { [weak self] pixelBuffer, timestamp in
            self?.detectionOrchestrator.processFrame(
                pixelBuffer: pixelBuffer,
                timestamp: CMTimeGetSeconds(timestamp)
            )
        }
        detectionOrchestrator.start()
    }

    func stopRecording() {
        guard isRecording else { return }
        detectionOrchestrator.stop()
        clearReplay()
        cameraService.onFrameCaptured = nil
        cameraService.onAudioCaptured = nil
        state = .finalizingVideo
        #if DEBUG
        DeviceProbe.event("recording_stopped", [
            "swings": String(detectedSwings.count),
            "duration_s": String(format: "%.1f", cameraService.recordedDuration)
        ], ui: true, frame: true)
        #endif
        Analytics.shared.track(.recordingStopped(swingCount: detectedSwings.count))
        cameraService.stopRecording()
        startFinalizeWatchdog()
    }

    /// Safety net for the two input-blocking overlay states. `.finalizingVideo`'s only
    /// normal exit is the `onRecordingFinished` callback, and `.saving` copies a file that
    /// can be hundreds of MB onto a device that may be out of space. If either never
    /// completes, the overlay would otherwise stay up forever with force-quit the only
    /// escape. Recover into `.reviewing` so the user keeps a manual Save/Delete path.
    private func startFinalizeWatchdog() {
        finalizeWatchdog?.cancel()
        finalizeWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.finalizeTimeout))
            guard !Task.isCancelled, let self else { return }
            guard self.state == .finalizingVideo || self.state == .saving else { return }
            AppLogger.camera.error("RecordingViewModel: finalize watchdog fired — recovering to .reviewing")
            #if DEBUG
            DeviceProbe.event("finalize_watchdog_fired", [
                "state": self.state.probeLabel,
                "timeout_s": String(Int(Self.finalizeTimeout))
            ], ui: true)
            #endif
            Analytics.shared.track(.recordingFinalizeTimeout(swingCount: self.detectedSwings.count))
            self.errorMessage = String(localized: "Finishing the recording took too long. Your clip is still here — tap Save to try again.", comment: "Error shown when the recording finalize step times out and the app recovers automatically")
            self.state = .reviewing
        }
    }

    private func cancelFinalizeWatchdog() {
        finalizeWatchdog?.cancel()
        finalizeWatchdog = nil
    }

    // MARK: - Playback

    func toggleFavorite(at index: Int) {
        guard detectedSwings.indices.contains(index) else { return }
        detectedSwings[index].isFavorite.toggle()
    }

    private static let speeds: [Float] = [0.25, 0.5, 1.0]

    func cyclePlaybackSpeed() {
        guard let nextIndex = Self.speeds.firstIndex(of: playbackSpeed).map({ $0 + 1 }) else {
            playbackSpeed = Self.speeds[0]
            return
        }
        playbackSpeed = Self.speeds[nextIndex % Self.speeds.count]
    }

    // MARK: - Save & Delete

    /// Keep the take, in the app. The whole recording is copied into app storage and the
    /// detected swings ride along as markers — the player already plays ranges from markers,
    /// so there is nothing to cut and nothing to export here.
    ///
    /// Deliberately touches Photos nowhere: the automatic path must not depend on a
    /// permission the user has every reason to refuse. Exporting to Photos stayed where it
    /// belongs — behind the share button on the player, where the user asks for it.
    func saveRecording() async {
        guard let url = recordingURL else { return }
        guard !libraryGateBlocksSave() else {
            Analytics.shared.track(.featureGateHit(feature: .unlimitedLibrary))
            requiresLibraryUpgrade = true
            return
        }
        state = .saving
        // `.saving` shows the same input-blocking overlay as `.finalizingVideo`, so it gets
        // the same watchdog: a stalled copy must not trap the user. Re-armed rather than
        // inherited, because the manual Save from `.reviewing` arrives with none running.
        startFinalizeWatchdog()
        let savedVideo = await persistToSwiftData(recordingURL: url)
        completePersistence(savedVideo: savedVideo, originalURL: url)
    }

    /// Returns to idle after the saved-state hand-off has been consumed
    /// (currently: auto-navigate to History). Distinct from `cancel()`,
    /// which also tears down the capture session.
    func dismissSavedState() {
        saveOutcome = nil
        state = .idle
    }

    private func libraryGateBlocksSave() -> Bool {
        guard let modelContext else { return false }
        return !LibraryGateService.canAddSwing(in: modelContext)
    }

    private func finalizeSave(with savedVideo: SwingVideo, originalURL: URL) {
        // "recording" for every take now: the whole clip plus its markers is the stored
        // artifact. The old "full"/"clip" split described which shape reached the Photos
        // library, and nothing reaches Photos on this path any more. `count` still carries
        // how many swings the take held.
        #if DEBUG
        DeviceProbe.event("save_succeeded", [
            "video_id": savedVideo.id.uuidString,
            "swings": String(detectedSwings.count)
        ], ui: true)
        #endif
        Analytics.shared.track(.swingSaved(saveType: "recording", count: detectedSwings.count))
        recordReviewPromptMilestone()
        saveOutcome = SaveOutcome(videoID: savedVideo.id, swingCount: detectedSwings.count)
        try? FileManager.default.removeItem(at: originalURL)
        recordingURL = nil
        detectedSwings.removeAll()
        reviewNotice = nil
        state = .saved
    }

    /// Counts towards the App Store review prompt. The only previous caller lived in
    /// RecordingSaveService, which is dead code — so the prompt had never once fired in
    /// production. Swings only: a take the user kept *because* detection found nothing is
    /// the worst possible moment to ask them how much they like the app.
    private func recordReviewPromptMilestone() {
        guard !detectedSwings.isEmpty else { return }
        ReviewPromptService.shared.recordSwingDetected()
    }

    /// The same two `VideoStorageService` calls an imported video makes
    /// (`VideoImportService.importVideo`) — copy into app storage, then build the
    /// `SwingVideo` from the stored URL. A recording only adds the detected swings as
    /// markers; there is no separate storage path for takes.
    private func persistToSwiftData(recordingURL: URL) async -> SwingVideo? {
        guard let modelContext else { return nil }

        do {
            let storedURL = try await copyToStorageOffMain(from: recordingURL)
            let swingVideo = await videoStorageService.createSwingVideo(from: storedURL)
            swingVideo.hasBeenAnalyzed = !detectedSwings.isEmpty
            swingVideo.analysisDate = detectedSwings.isEmpty ? nil : Date()

            modelContext.insert(swingVideo)

            for clip in detectedSwings {
                let marker = swingMarker(for: clip, within: swingVideo.duration)
                marker.video = swingVideo
                modelContext.insert(marker)
            }

            try modelContext.save()
            return swingVideo
        } catch {
            AppLogger.detection.error("Failed to persist swing data: \(error.localizedDescription)")
            return nil
        }
    }

    /// One detected swing as a stored marker, trimmed to the take that was actually
    /// captured.
    ///
    /// Detection projects a swing's end a second past impact — a moment the user may never
    /// have recorded, because Stop is theirs to tap on the ball. A marker naming footage the
    /// file does not contain is not harmless: AVFoundation does not refuse an overrunning
    /// source range, it pads the composition, so the comparison would play that swing out
    /// over black and align its impact against a follow-through that does not exist.
    ///
    /// A zero duration means metadata failed to load, in which case the clip's own times are
    /// the best information available. `SwingMarker.init` re-establishes the ordering.
    private func swingMarker(for clip: SwingClip, within duration: TimeInterval) -> SwingMarker {
        let limit = duration > 0 ? duration : clip.endTime
        let marker = SwingMarker(
            startTime: min(clip.startTime, limit),
            contactTime: min(clip.impactTime, limit),
            endTime: min(clip.endTime, limit)
        )
        marker.isAutoDetected = true
        marker.detectionConfidence = clip.confidence
        marker.isFavorite = clip.isFavorite
        return marker
    }

    /// The recording can be hundreds of MB; a synchronous `FileManager.copyItem` on the
    /// main actor froze the UI under the saving overlay. Under approachable concurrency
    /// (NonisolatedNonsendingByDefault) a plain `nonisolated async` method runs on the
    /// caller's actor — main — so `@concurrent` is required to force the global executor.
    @concurrent
    private nonisolated func copyToStorageOffMain(from url: URL) async throws -> URL {
        try VideoStorageService.shared.copyVideoToStorage(from: url)
    }

    func deleteRecording() {
        cancelFinalizeWatchdog()
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL = nil
        detectedSwings.removeAll()
        reviewNotice = nil
        saveOutcome = nil
        state = .idle
    }

    /// Abandon the take and return to `.idle` with the capture session LEFT RUNNING. The
    /// Camera tab owns a permanently-mounted preview now, so cancelling a countdown or a
    /// recording must not stop the session — a stop/start cycle costs seconds and would put
    /// back the black screen this restructure removed. `releaseCamera()` is what stops the
    /// session, for when the preview is going away too.
    func discardTake() {
        countdownTask?.cancel()
        countdownTask = nil
        cancelFinalizeWatchdog()
        detectionOrchestrator.stop()
        clearReplay()
        cameraService.onFrameCaptured = nil
        cameraService.onAudioCaptured = nil
        // Two distinct cases, and conflating them leaks files either way:
        //  * genuinely recording -> the file is still being written, so hand it to the discard
        //    path and let the delegate delete it on completion. onRecordingFinished is
        //    deliberately left installed here; it performs that cleanup.
        //  * not recording (e.g. cancelling from .reviewing) -> stopRecording() is a no-op, no
        //    delegate callback will ever arrive, so delete it inline or it leaks forever.
        if isRecording {
            urlPendingDiscard = recordingURL
        } else if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        cameraService.stopRecording()
        recordingURL = nil
        detectedSwings.removeAll()
        reviewNotice = nil
        saveOutcome = nil
        state = .idle
    }
}

// MARK: - Review Notice

/// What the Camera tab tells the user while it waits in `.reviewing`. The session is
/// paused for review, so the preview behind it is black — this text is the only thing on
/// screen explaining why Save and Delete are being offered.
///
/// Computed rather than stored statics so the copy is resolved in the current locale at the
/// moment it is shown, not frozen at first access.
struct ReviewNotice: Equatable {
    let title: String
    let message: String

    /// Detection found nothing. Said plainly, because the alternative — what shipped — was
    /// deleting the take without a word.
    static var noSwingDetected: ReviewNotice {
        ReviewNotice(
            title: String(localized: "No swing detected", comment: "Shown when a recording finished without a detected swing — as the title of the capture review panel and as the subtitle of the finishing-recording overlay"),
            message: String(localized: "We couldn't find a swing in this take. Keep the full clip anyway, or delete it and record another.", comment: "Body of the capture review panel when no swing was detected; the user chooses between the Save and Delete buttons below it")
        )
    }

    /// Everything else that lands in review: the save was blocked by the library gate, the
    /// finalize watchdog recovered, the copy into app storage failed. The copy
    /// names the two buttons and promises nothing about where the clip ends up — one of
    /// those routes is a user who just declined an upgrade, for whom "save to your library"
    /// would be a dead end straight back to the paywall.
    static var manualReview: ReviewNotice {
        ReviewNotice(
            title: String(localized: "Ready to review", comment: "Title on the capture review panel when a finished recording is waiting for the user to save or delete it"),
            message: String(localized: "Save this recording, or delete it and record another.", comment: "Body of the capture review panel prompting the user to choose between the Save and Delete buttons below it")
        )
    }
}

// MARK: - Session Start Slot

/// Where a camera bring-up leaves its answer. One per attempt: the bring-up cannot be
/// cancelled, so a wait we abandoned at the deadline must not be able to answer for the
/// next attempt.
private final class SessionStartSlot {
    private(set) var started: Bool?

    func record(_ started: Bool) {
        self.started = started
    }
}
